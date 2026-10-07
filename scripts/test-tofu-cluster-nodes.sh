#!/usr/bin/env bash
set -euo pipefail

if ! command -v tofu >/dev/null 2>&1; then
    echo "Error: OpenTofu is required for the cluster_nodes offline tests." >&2
    exit 1
fi

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
module_dir="$repo_dir/tofu/aws/modules/cluster_nodes"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/qa-cluster-nodes-test.XXXXXX")"
readonly test_dir

cleanup() {
    case "$test_dir" in
        */qa-cluster-nodes-test.??????)
            rm -rf -- "$test_dir"
            ;;
        *)
            echo "Refusing to clean unexpected test directory: $test_dir" >&2
            return 1
            ;;
    esac
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# Copy only module sources and fixtures, never local tfvars, backends or state.
cp "$module_dir"/{main.tf,variables.tf,outputs.tf,terraform.tf,.terraform.lock.hcl} "$test_dir/"
cp -R "$module_dir/tests" "$test_dir/tests"

# Keep inherited CLI/data settings from redirecting tests to an existing workspace.
unset TF_DATA_DIR TF_WORKSPACE TF_CLI_ARGS TF_CLI_ARGS_init TF_CLI_ARGS_validate TF_CLI_ARGS_test TF_CLI_ARGS_fmt

tofu -chdir="$test_dir" fmt -check main.tf variables.tf outputs.tf terraform.tf tests
tofu -chdir="$test_dir" init -backend=false -input=false -lockfile=readonly -no-color
tofu -chdir="$test_dir" validate -no-color
tofu -chdir="$test_dir" test -no-color
