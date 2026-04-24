#!/usr/bin/bash
# Usage:
#   ./init-backend.sh s3 --bucket <bucket> --key <key> --region <region> [--dynamodb-table <table>] [--encrypt true|false]
#   ./init-backend.sh local [--path <path>]
#
# This script generates ./backend.tf from templates/backend-<type>.tf.tmpl and runs:
#   tofu init -reconfigure
#
set -euo pipefail

# Set PATH for basic commands
export PATH="/usr/bin:/bin:/usr/local/bin"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES_DIR="$(dirname "$SCRIPT_DIR")/templates"
OUTFILE="backend.tf"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <s3|local> [options]"
  exit 2
fi

backend="$1"; shift

# Handle help flag first
if [ "$backend" = "--help" ] || [ "$backend" = "-h" ]; then
  echo "Usage: $0 <s3|local> [options]"
  echo ""
  echo "S3 Backend:"
  echo "  $0 s3 --bucket <bucket> --key <key> --region <region> [--dynamodb-table <table>] [--encrypt true|false]"
  echo ""
  echo "Local Backend:"
  echo "  $0 local [--path <path>]"
  echo ""
  echo "Examples:"
  echo "  $0 s3 --bucket my-bucket --key rke2-default/terraform.tfstate --region us-east-1"
  echo "  $0 local --path terraform.tfstate"
  exit 0
fi

# defaults
BUCKET=""
KEY=""
REGION=""
DYNAMODB_TABLE=""
ENCRYPT="true"
LOCAL_PATH="terraform.tfstate"

# parse args (simple)
while [ $# -gt 0 ]; do
  case "$1" in
    --bucket) BUCKET="$2"; shift 2;;
    --key) KEY="$2"; shift 2;;
    --region) REGION="$2"; shift 2;;
    --dynamodb-table) DYNAMODB_TABLE="$2"; shift 2;;
    --encrypt) ENCRYPT="$2"; shift 2;;
    --path) LOCAL_PATH="$2"; shift 2;;
    --help|-h) echo "See script header for usage"; exit 0;;
    *) echo "Unknown arg: $1"; exit 2;;
  esac
done

# ensure templates exist
tmpl="${TEMPLATES_DIR}/backend-${backend}.tf.tmpl"
if [ ! -f "$tmpl" ]; then
  echo "Template not found: $tmpl"
  exit 2
fi

# generate backend.tf
echo "Generating ${OUTFILE} from ${tmpl} ..."
case "$backend" in
  s3)
    if [ -z "$BUCKET" ] || [ -z "$KEY" ] || [ -z "$REGION" ]; then
      echo "For s3 backend you must provide --bucket, --key and --region"
      exit 2
    fi
    # fill placeholders in template
    sed -e "s|__BUCKET__|${BUCKET}|g" \
        -e "s|__KEY__|${KEY}|g" \
        -e "s|__REGION__|${REGION}|g" \
        -e "s|__DYNAMODB_TABLE__|${DYNAMODB_TABLE}|g" \
        -e "s|__ENCRYPT__|${ENCRYPT}|g" \
        "$tmpl" > "$OUTFILE"
    ;;
  local)
    sed -e "s|__PATH__|${LOCAL_PATH}|g" "$tmpl" > "$OUTFILE"
    ;;
  *)
    echo "Unsupported backend: $backend"
    exit 2
    ;;
esac

# Determine which CLI to use: tofu or terraform
if command -v tofu >/dev/null 2>&1; then
  TF_CLI="tofu"
elif command -v terraform >/dev/null 2>&1; then
  TF_CLI="terraform"
else
  echo "Error: Neither 'tofu' nor 'terraform' is installed or in PATH."
  exit 1
fi

echo "Generated ${OUTFILE} (add to .gitignore). Running ${TF_CLI} init -reconfigure ..."
${TF_CLI} init -reconfigure

echo "Done."
