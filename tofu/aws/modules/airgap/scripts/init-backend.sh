#!/usr/bin/env bash
# Usage:
#   ./scripts/init-backend.sh s3 --bucket <bucket> --key <key> --region <region> [--dynamodb-table <table>] [--encrypt true|false]
#   ./scripts/init-backend.sh local [--path <path>]
#
# This script generates ./backend.tf from templates/backend-<type>.tf.tmpl and runs:
#   terraform init -reconfigure
#
set -euo pipefail

TEMPLATES_DIR="$(dirname "$0")/../templates"
OUTFILE="backend.tf"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <s3|local> [options]"
  exit 2
fi

backend="$1"; shift

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

echo "Generated ${OUTFILE} (add to .gitignore). Running terraform init -reconfigure ..."
terraform init -reconfigure

echo "Done."