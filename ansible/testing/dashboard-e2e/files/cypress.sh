#!/bin/bash

set -e
trap 'echo "FAILED at line $LINENO: $BASH_COMMAND (exit $?)"' ERR

# Source shared utilities relative to the script's location
source "$(dirname "$0")/utils.sh"

pwd

# Undo everything this script changes in the checkout, so --dashboard-dir leaves
# a developer's tree as found. The only place every path shares.
_project_root="$PWD"
# Refuse to delete paths under anything that is not a dashboard checkout.
if [ -z "$_project_root" ] || [ ! -f "${_project_root}/cypress/package.json" ]; then
	echo "[cypress.sh] ERROR: ${_project_root:-<empty>} is not a dashboard checkout, no cypress/package.json found."
	exit 1
fi
# coreutils 9 also refuses to recurse across a mount point, which guards the
# checkout root. Older rm does not know the option.
_rm_guard=()
if rm --help 2>&1 | grep -q 'preserve-root\[=all\]'; then
	_rm_guard=(--preserve-root=all)
fi

# shellcheck disable=SC2329  # invoked by the EXIT trap below
_cleanup() {
	if [ -L "${_project_root}/node_modules" ] &&
		[ "$(readlink "${_project_root}/node_modules")" = "cypress/node_modules" ]; then
		rm -f "${_project_root}/node_modules" || true
	fi
}
trap _cleanup EXIT

# The container holds cloud credentials and reporting tokens. No install needs
# them.
_secret_env=(
	AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY
	AZURE_AKS_SUBSCRIPTION_ID AZURE_CLIENT_ID AZURE_CLIENT_SECRET
	CUSTOM_NODE_KEY GKE_SERVICE_ACCOUNT KUBECONFIG
	PERCY_TOKEN QASE_AUTOMATION_TOKEN TEST_PASSWORD
)
# Package manager for the checkout: bundled Yarn 1 for classic branches, the
# packageManager-pinned Yarn Berry via corepack for newer ones (set below).
_pm_yarn=(yarn)
_yarn_sealed() {
	local _drop=() _v
	for _v in "${_secret_env[@]}"; do _drop+=(-u "$_v"); done
	env "${_drop[@]}" NODE_NO_WARNINGS=1 "${_pm_yarn[@]}" "$@"
}

# Classic checkouts use Yarn 1 with --frozen-lockfile. Berry checkouts (yarn@4
# packageManager or a '__metadata:' lockfile) need corepack and --immutable.
_install_args=(install --frozen-lockfile --silent)
if grep -qs '"packageManager"[[:space:]]*:[[:space:]]*"yarn@[2-9]' cypress/package.json ||
	grep -qs '^__metadata:' cypress/yarn.lock; then
	if ! command -v corepack >/dev/null 2>&1; then
		echo "[cypress.sh] ERROR: checkout pins Yarn Berry but corepack is not in the image."
		exit 1
	fi
	_pm_yarn=(corepack yarn)
	_install_args=(install --immutable)
	export COREPACK_ENABLE_DOWNLOAD_PROMPT=0
	echo "[cypress.sh] Yarn Berry checkout: installing with 'corepack yarn ${_install_args[*]}'"
else
	echo "[cypress.sh] Classic Yarn checkout: installing with 'yarn ${_install_args[*]}'"
fi

# Install test dependencies inside the container (correct platform binaries for Debian/glibc)
echo "[cypress.sh] Installing test dependencies..."
echo "[cypress.sh] PWD=$(pwd)"
if ! (cd cypress && _yarn_sealed "${_install_args[@]}"); then
	echo "[cypress.sh] ERROR: yarn install failed in $(pwd)/cypress"
	echo "[cypress.sh] Node: $(node -v), Yarn: $( (cd cypress && "${_pm_yarn[@]}" --version) 2>/dev/null)"
	echo "[cypress.sh] package.json exists: $(test -f cypress/package.json && echo yes || echo no)"
	echo "[cypress.sh] yarn.lock exists: $(test -f cypress/yarn.lock && echo yes || echo no)"
	exit 1
fi

# Point ./node_modules at the test dependencies so anything resolving from the
# checkout root finds them. Only an absent node_modules or a link this script
# left is touched. A developer's own directory or link is left alone, since
# moving it aside would strand it if the run is killed. Removed by the trap.
if { [ ! -e node_modules ] && [ ! -L node_modules ]; } ||
	{ [ -L node_modules ] && [ "$(readlink node_modules)" = "cypress/node_modules" ]; }; then
	ln -sfn cypress/node_modules node_modules
else
	echo "[cypress.sh] NOTICE: ./node_modules already exists and is not ours, so it is left untouched."
	echo "[cypress.sh]         Test dependencies are read from cypress/node_modules either way."
fi

# Use test deps from cypress/node_modules
export NODE_PATH="${PWD}/cypress/node_modules:${NODE_PATH:-}"
export PATH="${PWD}/cypress/node_modules/.bin:${PATH}"
# Cypress evaluates the config from its own directory, so hand it the root.
export E2E_PROJECT_ROOT="$_project_root"
echo "[cypress.sh] node $(node -v), kubectl $(kubectl version --client -o json 2>/dev/null | grep -o '"gitVersion":"[^"]*"' || kubectl version --client --short 2>&1 | head -1)"

export FORCE_COLOR=1
export PERCY_LOGLEVEL=warn
export PERCY_SKIP_UPDATE_CHECK=true
# The @cypress/grep debug channel dumps the whole Cypress env object, which
# carries the AWS keys, the Azure client secret and the base64 SSH private key.
# Keep it off by default and make the operator opt in.
if [ "${CYPRESS_GREP_DEBUG:-false}" = "true" ]; then
	echo "[cypress.sh] WARNING: CYPRESS_GREP_DEBUG=true. @cypress/grep debug output prints credentials into this log. Do not share it."
	export DEBUG="${DEBUG:+$DEBUG,}@cypress/grep"
fi
export NODE_OPTIONS="--max-old-space-size=4096"

# Use CYPRESS_grepTags from env (.env file) if set; fall back to baked-in placeholder
TAGS="${CYPRESS_grepTags:-CYPRESSTAGS}"

# Normalize tags (strip @bypass, handle spaces)
TAGS=$(clean_tags "${TAGS}")

export CYPRESS_grepTags="$TAGS"

# Pre-filter specs by tag so Cypress only opens matching files.
# This bypasses the Cypress 11 bug where config.specPattern modifications
# from setupNodeEvents are ignored.
#
# Only an explicit --spec replaces that pre-filter. Any other forwarded flag
# (for example --browser) must not silently turn a tagged run into a full-suite
# run, so it is appended to the tag-derived arguments instead.
_spec_override=0
for arg in "$@"; do
	if [ "$arg" = "--spec" ]; then
		_spec_override=1
		break
	fi
done

SPEC_ARG=()
if [ "$_spec_override" -eq 1 ]; then
	SPEC_ARG=("$@")
	echo "cypress.sh: Using passed arguments: ${SPEC_ARG[*]}"

	# Belt-and-suspenders validation for --spec values inside the container.
	# Globs and comma lists are passed through for Cypress itself to resolve.
	i=1
	for arg in "$@"; do
		if [ "$arg" = "--spec" ]; then
			next_idx=$((i + 1))
			spec_val=""
			eval "spec_val=\${$next_idx:-}"
			case "$spec_val" in
			'' | *'*'* | *,*) ;;
			*)
				if [ ! -f "$spec_val" ]; then
					echo "[cypress.sh] ERROR: --spec file '$spec_val' does not exist inside the container at $(pwd)/$spec_val" >&2
					exit 1
				fi
				;;
			esac
		fi
		i=$((i + 1))
	done
else
	if [ -n "$TAGS" ]; then
		if ! FILTERED_SPECS=$(node --no-warnings --experimental-strip-types cypress/jenkins/grep-filter.ts); then
			echo "[cypress.sh] ERROR: grep-filter.ts failed:"
			echo "$FILTERED_SPECS"
			exit 1
		fi
		if [ -n "$FILTERED_SPECS" ]; then
			echo "grep-filter: will run --spec $FILTERED_SPECS"
			SPEC_ARG=(--spec "$FILTERED_SPECS")
		else
			echo "[cypress.sh] ERROR: no specs matched tags '$TAGS', nothing to run."
			echo "[cypress.sh] Check that cypress_tags matches tests available on this branch."
			exit 1
		fi
	fi

	if [ "$#" -gt 0 ]; then
		echo "cypress.sh: forwarding extra arguments: $*"
		SPEC_ARG+=("$@")
	fi
fi

# Chrome is installed into the image only when CHROME_VERSION is set, and not
# every version is built for every architecture, so a runner can end up without
# it. Fall back to Cypress's bundled Electron, which is always present. Detected
# rather than assumed, so the pin can move without touching this. Override with
# CYPRESS_BROWSER.
BROWSER="${CYPRESS_BROWSER:-chrome}"
if [ "$BROWSER" = chrome ] &&
	! command -v google-chrome >/dev/null 2>&1 &&
	! command -v google-chrome-stable >/dev/null 2>&1; then
	echo "[cypress.sh] Google Chrome not found (arch=$(uname -m)); falling back to --browser electron."
	BROWSER=electron
fi

# mocha-junit-reporter appends here rather than replacing, so a reused checkout
# would merge every earlier run's XML into results.xml. Absolute path, anchored
# to the checkout verified at the top.
_junit_dir="${_project_root}/cypress/jenkins/reports/junit"
rm -rf "${_rm_guard[@]}" -- "$_junit_dir"
mkdir -p -- "$_junit_dir"

# Run Cypress and capture the exit code
set +e

if [ -n "$PERCY_TOKEN" ]; then
	percy exec -q -- cypress run --browser "$BROWSER" --config-file cypress/jenkins/cypress.config.jenkins.ts "${SPEC_ARG[@]}"
else
	cypress run --browser "$BROWSER" --config-file cypress/jenkins/cypress.config.jenkins.ts "${SPEC_ARG[@]}"
fi
EXIT_CODE=$?
set -e

echo "CYPRESS EXIT CODE: $EXIT_CODE"

# Merge JUnit reports inside the container (Node.js is available here).
# Through PATH, not `npx --no-install`: npx resolves only against
# ./node_modules/.bin, and a developer's own root install there has no jrm.
echo "[cypress.sh] Merging JUnit reports..."
if ! jrm results.xml "cypress/jenkins/reports/junit/junit-*"; then
	echo "WARNING: jrm merge failed, so results.xml was not produced."
	if ! command -v jrm >/dev/null 2>&1; then
		echo "WARNING: junit-report-merger is not installed in this checkout, which is why the merge could not run."
	fi
	echo "WARNING: individual junit-*.xml files may still be available:"
	ls -la cypress/jenkins/reports/junit/ 2>/dev/null || echo "  (report directory not found)"
fi

exit $EXIT_CODE
