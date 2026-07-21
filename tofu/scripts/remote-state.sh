#!/usr/bin/bash
# remote-state.sh — Operate on OpenTofu state stored in an S3 backend.
#
# This complements the Makefile `infra-*` targets, which only scan LOCAL state
# files. When a module uses an S3 backend (the default in this repo), local
# `terraform.tfstate` files don't exist, so `make infra-ls` / `infra-nuke` see
# nothing. This script reads state directly from S3 so you can list, destroy,
# and clean up infrastructure that lives entirely in the remote backend.
#
# Usage:
#   remote-state.sh list          --module <dir> [--bucket B --key K --region R]
#                                  [--filter REGEX]
#   remote-state.sh destroy       --module <dir> [--bucket B --key K --region R]
#                                  [--var-file FILE] [--filter REGEX]
#                                  [--auto-approve] [--dry-run]
#   remote-state.sh empty-folders --module <dir> [--bucket B --key K --region R]
#                                  [--filter REGEX] [--purge] [--delete] [--auto-approve]
#   remote-state.sh stale-folders  --module <dir> [--bucket B --key K --region R]
#                                  [--filter REGEX] [--purge] [--delete] [--auto-approve]
#
# Backend discovery:
#   If --bucket/--key/--region are omitted, they are read from
#   <module>/backend.tf. In S3-backend workspaces, state lives at:
#       <key>                      # "default" workspace
#       env:/<workspace>/<key>     # every other workspace (workspace_key_prefix=env)
#
# Requirements: tofu (or terraform), aws CLI, python3.

set -euo pipefail

export PATH="/usr/bin:/bin:/usr/local/bin"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

die()  { echo "ERROR: $*" >&2; exit 1; }

# Pick the IaC CLI (tofu preferred, terraform fallback).
tf_cli() {
  if command -v tofu >/dev/null 2>&1; then printf 'tofu'
  elif command -v terraform >/dev/null 2>&1; then printf 'terraform'
  else die "Neither 'tofu' nor 'terraform' found in PATH."; fi
}

# Extract a backend attribute from <dir>/backend.tf.
# Usage: backend_attr <dir> <bucket|key|region>
backend_attr() {
  local dir="$1" name="$2"
  local f="$dir/backend.tf"
  [ -f "$f" ] || die "backend.tf not found in $dir (run 'make backend-s3' first)."
  # matches: bucket = "value"  /  key = "value"  /  region = "value"
  grep -E "^[[:space:]]*${name}[[:space:]]*=" "$f" \
    | head -1 \
    | sed -E 's/.*"([^"]*)".*/\1/' \
    | grep -E '.' \
    || die "Could not parse '$name' from $f."
}

# Count managed resources in a state JSON read from stdin.
count_managed() {
  python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
except Exception:
    print(0); sys.exit()
print(len([r for r in d.get('resources', []) if r.get('mode') == 'managed']))
"
}

# Resolve bucket/key/region from flags or backend.tf.
# Sets globals: BUCKET, KEY, REGION.
resolve_backend() {
  local module="$1"; shift
  BUCKET="${BUCKET:-$(backend_attr "$module" bucket)}"
  KEY="${KEY:-$(backend_attr "$module" key)}"
  REGION="${REGION:-$(backend_attr "$module" region)}"
  [ -n "$BUCKET" ] && [ -n "$KEY" ] && [ -n "$REGION" ] \
    || die "Could not resolve bucket/key/region."
}

# List S3 object keys holding state for this backend:
#   the default-workspace object (<KEY>) and every workspace object (env:/<ws>/<KEY>).
# Prints: "<workspace>\t<s3key>" lines.
list_state_keys() {
  local ws key
  # default workspace (object at <KEY>, no prefix)
  if aws s3api head-object --bucket "$BUCKET" --key "$KEY" --region "$REGION" >/dev/null 2>&1; then
    printf 'default\t%s\n' "$KEY"
  fi
  # workspaces: env:/<ws>/<KEY>
  while IFS= read -r s3key; do
    [ -n "$s3key" ] || continue
    # strip the leading "env:/" and the trailing "/$KEY"
    ws="${s3key#env:/}"
    ws="${ws%/$KEY}"
    # skip anything that isn't actually <ws>/<KEY>
    [ "$s3key" = "env:/$ws/$KEY" ] || continue
    [ -n "$ws" ] && printf '%s\t%s\n' "$ws" "$s3key"
  done < <(aws s3api list-objects-v2 --bucket "$BUCKET" --region "$REGION" \
             --prefix "env:/" --query 'Contents[].Key' --output text 2>/dev/null \
           | tr '\t' '\n' | grep -E '\.tfstate$' || true)
}

# Print "<workspace>\t<count>" for workspaces that have managed resources,
# optionally filtered by --filter REGEX (matched against workspace name).
scan_workspaces() {
  local filter="${FILTER:-}"
  while IFS=$'\t' read -r ws s3key; do
    if [ -n "$filter" ] && ! echo "$ws" | grep -qE "$filter"; then continue; fi
    local n
    n=$(aws s3 cp "s3://$BUCKET/$s3key" - --region "$REGION" --quiet 2>/dev/null | count_managed || echo 0)
    if [ "${n:-0}" -gt 0 ]; then
      printf '%s\t%s\n' "$ws" "$n"
    fi
  done < <(list_state_keys)
}

# Print "<workspace>\t<statekey>\t<folder_obj_count>" for workspaces whose state
# has ZERO managed resources — i.e. leftover "empty folders" left behind after
# `destroy` removed the resources but not the state object. Deleting these
# state objects makes the folder vanish from the S3 console.
scan_empty_workspaces() {
  local filter="${FILTER:-}" ws n objs s3key folder_prefix
  while IFS=$'\t' read -r ws s3key; do
    [ -n "$filter" ] && { echo "$ws" | grep -qE "$filter" || continue; }
    n=$(aws s3 cp "s3://$BUCKET/$s3key" - --region "$REGION" --quiet 2>/dev/null | count_managed || echo 0)
    [ "${n:-0}" -gt 0 ] && continue   # has resources → not empty
    if [ "$ws" = "default" ]; then folder_prefix=""; else folder_prefix="env:/$ws/"; fi
    if [ -n "$folder_prefix" ]; then
      objs=$(aws s3api list-objects-v2 --bucket "$BUCKET" --region "$REGION" --prefix "$folder_prefix" \
               --query 'Contents[].Key' --output text 2>/dev/null \
             | tr '\t' '\n' | grep -vE '^(None)?$' | grep -c . || echo 0)
    else
      objs=1
    fi
    printf '%s\t%s\t%s\n' "$ws" "$s3key" "${objs:-0}"
  done < <(list_state_keys)
}



# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------

cmd_list() {
  local module="" BUCKET="" KEY="" REGION="" FILTER=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --module) module="$2"; shift 2;;
      --bucket) BUCKET="$2"; shift 2;;
      --key)    KEY="$2";    shift 2;;
      --region) REGION="$2"; shift 2;;
      --filter) FILTER="$2"; shift 2;;
      *) die "list: unknown arg: $1";;
    esac
  done
  [ -n "$module" ] || die "list: --module is required (e.g. tofu/aws/modules/cluster_nodes)."
  [ -d "$module" ] || die "list: module dir not found: $module"
  resolve_backend "$module"

  echo "╔════════════════════════════════════════════════════════════════╗"
  echo "║  Remote state scanner (S3 backend)                            ║"
  echo "║  Module : $(printf '%-47s' "$module")"
  echo "║  Bucket : $(printf '%-47s' "$BUCKET")"
  echo "║  Key    : $(printf '%-47s' "$KEY")"
  echo "║  Region : $(printf '%-47s' "$REGION")"
  echo "╚════════════════════════════════════════════════════════════════╝"
  echo ""

  local found=0 total=0
  while IFS=$'\t' read -r ws n; do
    printf '  ACTIVE  %-44s %4s res\n' "$ws" "$n"
    found=1
    total=$((total + n))
  done < <(scan_workspaces)

  if [ "$found" -eq 0 ]; then
    echo "  No workspaces with managed resources found."
  else
    echo ""
    echo "  Total managed resources across listed workspaces: $total"
  fi
  echo ""
  echo "Destroy with:    make infra-nuke-remote$([ -n "$FILTER" ] && echo " NUKE_FILTER='$FILTER'")"
  echo "Prune folders:   make infra-empty-folders DELETE=yes"
}

cmd_destroy() {
  local module="" BUCKET="" KEY="" REGION="" VAR_FILE="" FILTER="" DRY_RUN=0 AUTO=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --module)    module="$2"; shift 2;;
      --bucket)    BUCKET="$2"; shift 2;;
      --key)       KEY="$2";    shift 2;;
      --region)    REGION="$2"; shift 2;;
      --var-file)  VAR_FILE="$2"; shift 2;;
      --filter)    FILTER="$2"; shift 2;;
      --dry-run)   DRY_RUN=1; shift;;
      --auto-approve) AUTO=1; shift;;
      *) die "destroy: unknown arg: $1";;
    esac
  done
  [ -n "$module" ] || die "destroy: --module is required."
  [ -d "$module" ] || die "destroy: module dir not found: $module"
  resolve_backend "$module"

  local TF; TF="$(tf_cli)"
  [ -n "$VAR_FILE" ] && [ ! -f "$module/$VAR_FILE" ] \
    && { echo "NOTE: var-file '$VAR_FILE' not found in $module; destroying without it."; VAR_FILE=""; }

  # Collect workspaces to destroy.
  local targets=()
  while IFS=$'\t' read -r ws n; do
    targets+=("$ws")
  done < <(scan_workspaces)

  echo "WARNING: destroying ${#targets[@]} remote workspace(s) in $BUCKET ($module)."
  if [ "$DRY_RUN" -eq 1 ]; then echo "[DRY-RUN]"; fi
  echo ""
  for ws in "${targets[@]}"; do printf '  - %s\n' "$ws"; done
  echo ""

  if [ "$AUTO" -ne 1 ] && [ "$DRY_RUN" -ne 1 ]; then
    if [ ! -t 0 ]; then
      die "stdin is not a TTY and --auto-approve not set. Re-run with AUTO_APPROVE=yes."
    fi
    read -p "Destroy ALL listed workspaces? Type 'nuke' to confirm: " confirm
    [ "$confirm" = "nuke" ] || { echo "Aborted."; exit 1; }
  fi

  if [ "$DRY_RUN" -eq 1 ]; then
    echo "Dry run: would destroy ${#targets[@]} workspace(s). No changes made."
    exit 0
  fi

  local errors=0 var_args=()
  [ -n "$VAR_FILE" ] && var_args=(-var-file="$VAR_FILE")

  ( cd "$module" && "$TF" init -input=false >/dev/null )

  for ws in "${targets[@]}"; do
    echo "────────────────────────────────────────────────────────────────"
    echo "Destroying workspace '$ws' ..."
    if ( cd "$module" \
         && "$TF" workspace select "$ws" >/dev/null 2>&1 \
         && "$TF" destroy -auto-approve "${var_args[@]}" ); then
      echo "✓ destroyed: $ws"
    else
      echo "✗ FAILED: $ws (destroy manually)"
      errors=$((errors + 1))
    fi
  done

  echo ""
  if [ "$errors" -gt 0 ]; then
    echo "WARNING: $errors workspace(s) failed to destroy. Re-run after fixing, or"
    echo "         destroy those manually with 'tofu workspace select <ws> && tofu destroy'."
    exit 1
  fi
  echo "✓ All remote workspaces destroyed."
}



cmd_empty_folders() {
  local module="" BUCKET="" KEY="" REGION="" FILTER="" PURGE=0 DELETE=0 AUTO=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --module)    module="$2"; shift 2;;
      --bucket)    BUCKET="$2"; shift 2;;
      --key)       KEY="$2";    shift 2;;
      --region)    REGION="$2"; shift 2;;
      --filter)    FILTER="$2"; shift 2;;
      --purge)     PURGE=1; shift;;
      --delete)    DELETE=1; shift;;
      --auto-approve) AUTO=1; shift;;
      *) die "empty-folders: unknown arg: $1";;
    esac
  done
  [ -n "$module" ] || die "empty-folders: --module is required (e.g. tofu/aws/modules/cluster_nodes)."
  [ -d "$module" ] || die "empty-folders: module dir not found: $module"
  resolve_backend "$module"

  echo "╔═════════════════════════════════════════════════════════════╗"
  echo "║  Empty workspace-folder scanner (S3 backend)             ║"
  echo "║  Bucket : $(printf '%-42s' "$BUCKET")"
  echo "║  Key    : $(printf '%-42s' "$KEY")"
  echo "╚═════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Folders whose state has 0 managed resources (leftover after destroy):"
  echo ""

  local rows=() ws s3key objs entry folder_prefix
  while IFS=$'\t' read -r ws s3key objs; do
    rows+=("$ws|$s3key|$objs")
    printf '  %-40s %3s obj(s)  %s\n' "$ws" "${objs:-0}" "$s3key"
  done < <(scan_empty_workspaces)

  if [ "${#rows[@]}" -eq 0 ]; then
    echo "  (none)"
    return 0
  fi
  echo ""

  if [ "$DELETE" -ne 1 ]; then
    echo "Not deleting — pass --delete (or: make infra-empty-folders DELETE=yes)."
    [ "$PURGE" -eq 1 ] && echo "  --purge would also delete all objects under each folder, not just the state."
    return 0
  fi

  echo "WARNING: deleting ${#rows[@]} empty workspace folder(s) from $BUCKET."
  [ "$PURGE" -eq 1 ] && echo "  (--purge: removing ALL objects under each folder, not just the state)"
  if [ "$AUTO" -ne 1 ]; then
    if [ ! -t 0 ]; then die "stdin is not a TTY and --auto-approve not set."; fi
    read -p "Type 'prune' to confirm: " confirm
    [ "$confirm" = "prune" ] || { echo "Aborted."; exit 1; }
  fi
  echo ""

  local errors=0 rest
  for entry in "${rows[@]}"; do
    ws="${entry%%|*}"; objs="${entry##*|}"; rest="${entry#*|}"; s3key="${rest%|*}"
    if [ "$ws" = "default" ]; then folder_prefix=""; else folder_prefix="env:/$ws/"; fi
    if [ "$PURGE" -eq 1 ] && [ -n "$folder_prefix" ]; then
      echo "  purging s3://$BUCKET/$folder_prefix ..."
      if aws s3 rm "s3://$BUCKET/$folder_prefix" --recursive --region "$REGION" >/dev/null 2>&1; then
        echo "  ✓ pruned folder: $ws"
      else
        echo "  ✗ FAILED: $ws"; errors=$((errors + 1))
      fi
    else
      if aws s3 rm "s3://$BUCKET/$s3key" --region "$REGION" >/dev/null 2>&1; then
        echo "  ✓ deleted state: $ws ($s3key)"
      else
        echo "  ✗ FAILED: $ws ($s3key)"; errors=$((errors + 1))
      fi
    fi
  done
  echo ""
  if [ "$errors" -gt 0 ]; then
    echo "WARNING: $errors folder(s) failed to delete."
    exit 1
  fi
  echo "✓ Empty workspace folders removed."
}

# Extract "<region>\t<id1>,<id2>,..." from a state JSON on stdin.
# Region is taken from the first aws_lb ARN, falling back to an instance AZ.
state_region_and_instances() {
  python3 -c "
import sys, json, re
d = json.load(sys.stdin)
region = None
ids = []
for r in d.get('resources', []):
    for inst in r.get('instances', []):
        a = inst.get('attributes', {})
        if r['type'] == 'aws_instance' and a.get('id'):
            ids.append(a['id'])
        if not region:
            m = re.search(r'elasticloadbalancing:([a-z0-9-]+):', str(a.get('arn', '')))
            if m:
                region = m.group(1)
            elif a.get('availability_zone'):
                region = a['availability_zone'][:-1]
print('%s\t%s' % (region or '', ','.join(ids)))
"
}

# Return 0 (true) if NONE of the given instance IDs exist in <region>.
# Usage: instances_all_gone <region> <comma-separated-ids>
instances_all_gone() {
  local r="$1" ids="$2"
  [ -n "$r" ] && [ -n "$ids" ] || return 1   # can't tell → treat as not-gone (safe)
  local out
  out=$(aws ec2 describe-instances --region "$r" --instance-ids ${ids//,/ } \
         --query 'Reservations[].Instances[].InstanceId' --output text 2>&1 || true)
  case "$out" in
    *InvalidInstanceID.NotFound*) return 0;;   # AWS says none of them exist
  esac
  local existing
  existing=$(printf '%s' "$out" | tr '\t' '\n' | grep -vE '^(None)?$' | grep -c . || true)
  [ "${existing:-0}" -eq 0 ]
}

cmd_stale_folders() {
  local module="" BUCKET="" KEY="" REGION="" FILTER="" PURGE=0 DELETE=0 AUTO=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --module)    module="$2"; shift 2;;
      --bucket)    BUCKET="$2"; shift 2;;
      --key)       KEY="$2";    shift 2;;
      --region)    REGION="$2"; shift 2;;
      --filter)    FILTER="$2"; shift 2;;
      --purge)     PURGE=1; shift;;
      --delete)    DELETE=1; shift;;
      --auto-approve) AUTO=1; shift;;
      *) die "stale-folders: unknown arg: $1";;
    esac
  done
  [ -n "$module" ] || die "stale-folders: --module is required (e.g. tofu/aws/modules/cluster_nodes)."
  [ -d "$module" ] || die "stale-folders: module dir not found: $module"
  resolve_backend "$module"

  echo "╔═════════════════════════════════════════════════════════════╗"
  echo "║  Stale workspace-folder scanner (verified against AWS)   ║"
  echo "║  Bucket : $(printf '%-42s' "$BUCKET")"
  echo "║  Key    : $(printf '%-42s' "$KEY")"
  echo "╚═════════════════════════════════════════════════════════════╝"
  echo ""
  echo "Checking each workspace: state lists resources, but are they gone in AWS?"
  echo ""

  local rows=() ws s3key info reg ids entry folder_prefix
  local checked=0 stale=0 unknown=0
  while IFS=$'\t' read -r ws s3key; do
    [ -n "$FILTER" ] && { echo "$ws" | grep -qE "$FILTER" || continue; }
    # only consider workspaces that HAVE managed resources (empty ones use empty-folders)
    local n
    n=$(aws s3 cp "s3://$BUCKET/$s3key" - --region "$REGION" --quiet 2>/dev/null | count_managed || echo 0)
    [ "${n:-0}" -gt 0 ] || continue
    checked=$((checked + 1))
    info=$(aws s3 cp "s3://$BUCKET/$s3key" - --region "$REGION" --quiet 2>/dev/null | state_region_and_instances || true)
    reg=""; ids=""
    while IFS=$'\t' read -r r i; do reg="$r"; ids="$i"; done <<< "$info"
    if [ -z "$reg" ] || [ -z "$ids" ]; then
      printf '  %-40s  UNKNOWN (no instances/region in state)\n' "$ws"
      unknown=$((unknown + 1)); continue
    fi
    if instances_all_gone "$reg" "$ids"; then
      printf '  STALE   %-36s  [%s] %d instances gone\n' "$ws" "$reg" "$(echo "$ids" | tr ',' '\n' | wc -l | tr -d ' ')"
      rows+=("$ws|$s3key")
      stale=$((stale + 1))
    else
      printf '  LIVE    %-36s  [%s] instances still exist\n' "$ws" "$reg"
    fi
  done < <(list_state_keys)
  echo ""
  echo "Scanned: $checked  |  STALE: $stale  |  LIVE: skipped  |  UNKNOWN: $unknown"
  echo ""

  if [ "${#rows[@]}" -eq 0 ]; then
    echo "No stale workspace folders found."
    return 0
  fi

  if [ "$DELETE" -ne 1 ]; then
    echo "Not deleting — pass --delete (or: make infra-stale-folders DELETE=yes)."
    [ "$PURGE" -eq 1 ] && echo "  --purge would also delete all objects under each folder, not just the state."
    echo "  (Only removes workspaces whose AWS instances are confirmed gone.)"
    return 0
  fi

  echo "WARNING: deleting $stale STALE workspace state object(s) from $BUCKET."
  echo "  These were verified to have NO live instances in AWS."
  [ "$PURGE" -eq 1 ] && echo "  (--purge: removing ALL objects under each folder, not just the state)"
  if [ "$AUTO" -ne 1 ]; then
    if [ ! -t 0 ]; then die "stdin is not a TTY and --auto-approve not set."; fi
    read -p "Type 'prune-stale' to confirm: " confirm
    [ "$confirm" = "prune-stale" ] || { echo "Aborted."; exit 1; }
  fi
  echo ""

  local errors=0
  for entry in "${rows[@]}"; do
    ws="${entry%%|*}"; s3key="${entry#*|}"
    if [ "$ws" = "default" ]; then folder_prefix=""; else folder_prefix="env:/$ws/"; fi
    if [ "$PURGE" -eq 1 ] && [ -n "$folder_prefix" ]; then
      echo "  purging s3://$BUCKET/$folder_prefix ..."
      if aws s3 rm "s3://$BUCKET/$folder_prefix" --recursive --region "$REGION" >/dev/null 2>&1; then
        echo "  ✓ pruned: $ws"
      else
        echo "  ✗ FAILED: $ws"; errors=$((errors + 1))
      fi
    else
      if aws s3 rm "s3://$BUCKET/$s3key" --region "$REGION" >/dev/null 2>&1; then
        echo "  ✓ removed stale state: $ws"
      else
        echo "  ✗ FAILED: $ws"; errors=$((errors + 1))
      fi
    fi
  done
  echo ""
  if [ "$errors" -gt 0 ]; then
    echo "WARNING: $errors folder(s) failed to delete."
    exit 1
  fi
  echo "✓ Stale workspace folders removed."
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

[ $# -ge 1 ] || { sed -n '1,34p' "$0"; exit 2; }
cmd="$1"; shift
case "$cmd" in
  list)          cmd_list "$@";;
  destroy)       cmd_destroy "$@";;
  empty-folders) cmd_empty_folders "$@";;
  stale-folders)  cmd_stale_folders "$@";;
  -h|--help|help) sed -n '1,34p' "$0";;
  *) die "Unknown command '$cmd'. See: $0 --help";;
esac
