#!/bin/bash

set -e
trap 'echo "FAILED at line $LINENO: $BASH_COMMAND (exit $?)"' ERR

# Source shared utilities relative to the script's location
source "$(dirname "$0")/utils.sh"

pwd

# Install test dependencies inside the container (correct platform binaries for Debian/glibc)
echo "[cypress.sh] Installing test dependencies..."
echo "[cypress.sh] PWD=$(pwd)"
if ! (cd cypress && NODE_NO_WARNINGS=1 yarn install --frozen-lockfile --silent); then
	echo "[cypress.sh] ERROR: yarn install failed in $(pwd)/cypress"
	echo "[cypress.sh] Node: $(node -v), Yarn: $(yarn --version)"
	echo "[cypress.sh] package.json exists: $(test -f cypress/package.json && echo yes || echo no)"
	echo "[cypress.sh] yarn.lock exists: $(test -f cypress/yarn.lock && echo yes || echo no)"
	exit 1
fi
# Packages this checkout does not declare, at versions pinned by the playbook.
# grep-filter.ts requires globby and find-test-names directly and exits 1
# without them.
if [ -n "${MISSING_RUNTIME_DEPS:-}" ]; then
echo "[cypress.sh] Installing packages this checkout does not declare: ${MISSING_RUNTIME_DEPS}"
# --no-lockfile because these are additions on top of the checkout's lockfile,
# not a change to what it pins. Unquoted on purpose: a space separated list of
# name@version pairs that has to split into separate arguments.
# shellcheck disable=SC2086
if ! (cd cypress && NODE_NO_WARNINGS=1 yarn add --no-lockfile --silent ${MISSING_RUNTIME_DEPS}); then
echo "[cypress.sh] ERROR: could not install ${MISSING_RUNTIME_DEPS}"
echo "[cypress.sh] Tag filtering and JUnit reporting both need these."
exit 1
fi
fi

# Point ./node_modules at the test dependencies. -n stops ln from following an
# existing symlink and leaving a dangling link inside its target on repeat
# --dashboard-dir runs. A real directory is left alone: that is a developer's
# own root install, and ln would nest inside it rather than replace it.
if [ -L node_modules ] || [ ! -e node_modules ]; then
	ln -sfn cypress/node_modules node_modules
else
	echo "[cypress.sh] node_modules is a real directory; leaving it in place (NODE_PATH still points at cypress/node_modules)."
fi

# Use test deps from cypress/node_modules
export NODE_PATH="${PWD}/cypress/node_modules:${NODE_PATH:-}"
export PATH="${PWD}/cypress/node_modules/.bin:${PATH}"

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

# Google Chrome in the cypress/factory image is amd64-only, so it is absent on
# arm64 runners (Apple Silicon under Docker Desktop). Fall back to Cypress's
# bundled Electron, which is arm64-native. Override with CYPRESS_BROWSER.
BROWSER="${CYPRESS_BROWSER:-chrome}"
if [ "$BROWSER" = chrome ] &&
	! command -v google-chrome >/dev/null 2>&1 &&
	! command -v google-chrome-stable >/dev/null 2>&1; then
	echo "[cypress.sh] Google Chrome not found (arch=$(uname -m)); falling back to --browser electron."
	BROWSER=electron
fi

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

# Merge JUnit reports inside the container (Node.js is available here)
echo "[cypress.sh] Merging JUnit reports..."
if ! npx --no-install jrm results.xml "cypress/jenkins/reports/junit/junit-*"; then
	echo "WARNING: jrm merge failed, so results.xml was not produced."
	if ! npx --no-install jrm --version >/dev/null 2>&1; then
		echo "WARNING: junit-report-merger is not installed in this checkout, which is why the merge could not run."
	fi
	echo "WARNING: individual junit-*.xml files may still be available:"
	ls -la cypress/jenkins/reports/junit/ 2>/dev/null || echo "  (report directory not found)"
fi

exit $EXIT_CODE
