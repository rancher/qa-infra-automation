#!/bin/sh
# Wrapper to run the dashboard-e2e playbook inside a container.
# Works with Docker and Podman — no local tool installation needed.
#
# Commands:
#   ./run.sh                          # full pipeline (provision → test → cleanup)
#   ./run.sh provision                # provision infra only
#   ./run.sh setup                    # clone repo + build test image
#   ./run.sh test                     # re-run tests only
#   ./run.sh provision setup          # provision + setup (no test)
#   ./run.sh setup test               # setup + test (most common)
#   ./run.sh provision setup test     # everything except cleanup
#   ./run.sh stream                   # setup + test with live Cypress output
#   ./run.sh stream provision         # provision + setup + test, live output
#   ./run.sh destroy                  # tear down infrastructure
#   ./run.sh build                    # rebuild the runner image
#   ./run.sh results                  # open the HTML test report
#   ./run.sh clean                    # remove local artifacts (reports, clone, .env)
#
# Extra ansible flags pass through:
#   ./run.sh test -v                  # verbose
#   ./run.sh test --check             # dry-run
#
# Prerequisites:
#   - Docker or Podman
#   - vars.yaml in this directory (cp vars.yaml.example vars.yaml)
#   - AWS credentials exported (for provision): AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
#   - Windows: requires WSL2 (run from a WSL2 terminal)

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
IMAGE_NAME="dashboard-e2e-runner"
VARS_FILE="${SCRIPT_DIR}/vars.yaml"

# --- Detect container runtime ---
detect_runtime() {
	if command -v podman >/dev/null 2>&1; then
		RUNTIME="podman"
	elif command -v docker >/dev/null 2>&1; then
		RUNTIME="docker"
	else
		echo "" >&2
		echo "  You need Docker or Podman to run this." >&2
		echo "" >&2
		echo "  Install one of:" >&2
		echo "    Docker:  https://docs.docker.com/get-docker/" >&2
		echo "    Podman:  https://podman.io/docs/installation" >&2
		echo "" >&2
		echo "  Then re-run: ./run.sh" >&2
		echo "" >&2
		exit 1
	fi
}

# --- Detect container socket ---
detect_socket() {
	if [ "$RUNTIME" = "podman" ]; then
		for _sock in \
			"$(podman info -f '{{.Host.RemoteSocket.Path}}' 2>/dev/null || true)" \
			"/run/user/$(id -u)/podman/podman.sock" \
			"/run/podman/podman.sock"; do
			[ -n "$_sock" ] && [ -S "$_sock" ] && {
				SOCKET="$_sock"
				return
			}
		done
		echo "ERROR: Podman socket not found." >&2
		echo "Start it with:" >&2
		echo "  Linux:  systemctl --user start podman.socket" >&2
		echo "  macOS:  podman machine start" >&2
		exit 1
	else
		SOCKET="/var/run/docker.sock"
		if [ ! -S "$SOCKET" ]; then
			echo "ERROR: Docker socket not found at $SOCKET" >&2
			echo "Is Docker running?" >&2
			exit 1
		fi
	fi
}

# --- Build image if needed ---
build_image() {
	if ! $RUNTIME image inspect "$IMAGE_NAME" >/dev/null 2>&1 || [ "${_FORCE_BUILD:-}" = "1" ]; then
		echo "[run] Building ${IMAGE_NAME} image (first time takes ~2 min)..."
		$RUNTIME build -f "${SCRIPT_DIR}/Dockerfile.quickstart" -t "$IMAGE_NAME" "$SCRIPT_DIR"
	fi
}

# --- Run playbook inside container ---
run_playbook() {
	# Write credentials to a temp YAML file so special characters (=, spaces, quotes)
	# in token values are handled safely. Single-quoted YAML scalars accept any char.
	_creds_file="${SCRIPT_DIR}/.creds.yml"
	trap 'rm -f "${_creds_file}"' EXIT
	: > "${_creds_file}"
	chmod 600 "${_creds_file}"

	# Escape single quotes inside a single-quoted YAML scalar (' → '''')
	yaml_cred_escape() { printf '%s' "${1}" | sed "s/'/''''/g"; }

	[ -n "${QASE_TOKEN:-}" ]                && printf "qase_token: '%s'\n"            "$(yaml_cred_escape "${QASE_TOKEN}")"                >> "${_creds_file}"
	[ -n "${PERCY_TOKEN:-}" ]               && printf "percy_token: '%s'\n"           "$(yaml_cred_escape "${PERCY_TOKEN}")"               >> "${_creds_file}"
	[ -n "${AZURE_CLIENT_ID:-}" ]           && printf "azure_client_id: '%s'\n"       "$(yaml_cred_escape "${AZURE_CLIENT_ID}")"           >> "${_creds_file}"
	[ -n "${AZURE_CLIENT_SECRET:-}" ]       && printf "azure_client_secret: '%s'\n"   "$(yaml_cred_escape "${AZURE_CLIENT_SECRET}")"       >> "${_creds_file}"
	[ -n "${AZURE_AKS_SUBSCRIPTION_ID:-}" ] && printf "azure_subscription_id: '%s'\n" "$(yaml_cred_escape "${AZURE_AKS_SUBSCRIPTION_ID}")" >> "${_creds_file}"
	[ -n "${GKE_SERVICE_ACCOUNT:-}" ]       && printf "gke_service_account: '%s'\n"   "$(yaml_cred_escape "${GKE_SERVICE_ACCOUNT}")"       >> "${_creds_file}"

	# Ansible requires a valid YAML dict; fall back to empty mapping if no creds were written
	[ ! -s "${_creds_file}" ] && printf '{}\n' > "${_creds_file}"

	$RUNTIME run --rm -it \
		-v "${SOCKET}:/var/run/docker.sock" \
		-v "${VARS_FILE}:/playbook/vars.yaml:ro" \
		-v "${_creds_file}:/playbook/.creds.yml:ro" \
		-v "${SCRIPT_DIR}:/playbook" \
		-v "${REPO_ROOT}:/qa-infra" \
		-e QA_INFRA_DIR=/qa-infra \
		-e HOST_DASHBOARD_DIR="${SCRIPT_DIR}/dashboard" \
		-e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}" \
		-e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}" \
		"$IMAGE_NAME" \
		--extra-vars "@/playbook/.creds.yml" \
		"$@"

	rm -f "${_creds_file}"
}

# --- Stream Cypress with live output ---
stream_cypress() {
	echo ""
	echo "[run] Streaming Cypress tests..."
	echo ""

	if ! $RUNTIME image inspect dashboard-test:0 >/dev/null 2>&1; then
		echo "ERROR: dashboard-test:0 image not found — setup may have failed" >&2
		exit 1
	fi
	if [ ! -f "${SCRIPT_DIR}/.env" ]; then
		echo "ERROR: .env not found — setup may have failed" >&2
		exit 1
	fi

	_host="$(grep '^rancher_host:' "$VARS_FILE" 2>/dev/null | head -1 | sed "s/^rancher_host:[[:space:]]*//" | tr -d "\"'" || echo "dashboard-e2e")"
	_name="cypress-$(echo "$_host" | sed 's/[^a-zA-Z0-9_.-]/-/g')"
	$RUNTIME rm -f "$_name" 2>/dev/null || true

	exec $RUNTIME run --rm -it \
		--name "$_name" \
		--shm-size=2g \
		--env-file "${SCRIPT_DIR}/.env" \
		-e NODE_PATH="" \
		-v "${SCRIPT_DIR}/dashboard:/e2e" \
		-w /e2e \
		dashboard-test:0
}

# --- Main ---
detect_runtime
detect_socket

# Parse commands: known verbs become tags, rest passes to ansible
TAGS=""
STREAM=""
_FORCE_BUILD=""
_BUILD_ONLY=""
while [ $# -gt 0 ]; do
	case "$1" in
	provision | setup | test)
		TAGS="${TAGS:+${TAGS},}$1"
		shift
		;;
	stream)
		STREAM=1
		shift
		;;
	destroy)
		TAGS="cleanup,never"
		shift
		;;
	build)
		_FORCE_BUILD=1
		_BUILD_ONLY=1
		shift
		;;
	results)
		_report="${SCRIPT_DIR}/dashboard/cypress/reports/html/index.html"
		if [ -f "$_report" ]; then
			open "$_report" 2>/dev/null || xdg-open "$_report" 2>/dev/null || echo "$_report"
		else
			echo "No report found. Run tests first: ./run.sh stream"
		fi
		exit 0
		;;
	clean)
		rm -rf "${SCRIPT_DIR}/dashboard" "${SCRIPT_DIR}/outputs" "${SCRIPT_DIR}/.env"
		echo "[run] Local artifacts cleaned."
		exit 0
		;;
	--build)
		_FORCE_BUILD=1
		shift
		;;
	-h | --help)
		sed -n '2,/^$/s/^# //p' "$0"
		exit 0
		;;
	*)
		break
		;;
	esac
done

# stream without explicit stages defaults to setup,test
if [ -n "$STREAM" ] && [ -z "$TAGS" ]; then
	TAGS="setup,test"
fi

# Check vars.yaml
if [ ! -f "$VARS_FILE" ]; then
	echo "" >&2
	echo "  vars.yaml not found — let's set it up:" >&2
	echo "" >&2
	echo "    cp vars.yaml.example vars.yaml" >&2
	echo "    \$EDITOR vars.yaml" >&2
	echo "" >&2
	echo "  At minimum, set:" >&2
	echo "    rancher_host, rancher_password, rancher_image_tag, cypress_tags" >&2
	echo "" >&2
	exit 1
fi

# Warn if AWS creds are missing and provisioning is needed
case "${TAGS}" in
*provision* | "")
	if [ -z "${AWS_ACCESS_KEY_ID:-}" ] || [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
		echo "WARNING: AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY not set." >&2
		echo "These are required for provisioning." >&2
		echo "" >&2
	fi
	;;
esac

build_image

if [ -n "$_BUILD_ONLY" ]; then
	echo "[run] Image rebuilt. Done."
	exit 0
fi

mkdir -p "${SCRIPT_DIR}/outputs"

echo "[run] Using ${RUNTIME} (socket: ${SOCKET})"
echo "[run] vars.yaml: ${VARS_FILE}"
echo ""

# Build ansible tag args
TAG_ARGS=""
if [ -n "$TAGS" ]; then
	TAG_ARGS="--tags ${TAGS}"
fi

if [ -n "$STREAM" ]; then
	# Run everything except test via playbook, then stream Cypress directly
	# shellcheck disable=SC2086
	run_playbook --skip-tags test ${TAG_ARGS} "$@"
	stream_cypress
else
	# shellcheck disable=SC2086
	run_playbook ${TAG_ARGS} "$@"
fi
