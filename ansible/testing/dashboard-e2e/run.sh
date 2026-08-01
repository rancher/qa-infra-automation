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
# Options:
#   --dashboard-dir <path>           use a local dashboard checkout (skip clone)
#   --spec <path>                    run a single Cypress spec (relative to
#                                    dashboard dir; requires 'stream')
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
	# Docker Desktop on macOS installs its CLI under ~/.docker/bin, which is not
	# always on PATH (e.g. when the shell is managed outside Docker's installer).
	# Add it so `command -v docker` can find it.
	if [ -x "${HOME}/.docker/bin/docker" ]; then
		case ":${PATH}:" in
		*":${HOME}/.docker/bin:"*) ;;
		*) PATH="${HOME}/.docker/bin:${PATH}" ;;
		esac
	fi

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
		for _sock in \
			"/var/run/docker.sock" \
			"${HOME}/.docker/run/docker.sock"; do
			if [ -S "$_sock" ]; then
				SOCKET="$_sock"
				return
			fi
		done
		echo "ERROR: Docker socket not found at /var/run/docker.sock or ${HOME}/.docker/run/docker.sock" >&2
		echo "Is Docker running?" >&2
		exit 1
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

	# When --dashboard-dir is set, mount the external dir and pass it as an Ansible var
	_dashboard_vol=""
	if [ -n "${DASHBOARD_DIR:-}" ]; then
		_dashboard_vol="${DASHBOARD_DIR}:/external-dashboard"
	fi

	# --userns=keep-id is Podman-only; on Docker we rely on --user alone
	_userns=""
	[ "$RUNTIME" = "podman" ] && _userns="--userns=keep-id"

	# Keep the pseudo-tty for coloured Ansible output, but only bind stdin when
	# there is a terminal to bind. Without this the run dies immediately under
	# ssh in batch mode, cron, or any other non-interactive caller.
	_stdin=""
	[ -t 0 ] && _stdin="-i"

	# On Docker the socket keeps its host ownership (root:docker) inside the
	# container, and the unprivileged --user has no supplementary groups.
	# Grant the socket's gid explicitly. Rootless Podman sockets are already
	# owned by the invoking user, so nothing is needed there.
	_sock_gid=""
	if [ "$RUNTIME" = "docker" ]; then
		_sock_gid="$(stat -c '%g' "$SOCKET" 2>/dev/null || stat -f '%g' "$SOCKET" 2>/dev/null || true)"
	fi

	# tasks/run-tests.yml turns these into "--user <uid>:<gid>" on the Cypress
	# container so Docker leaves artifacts owned by the host user instead of
	# root. Rootless Podman needs the opposite: it has no --userns=keep-id
	# equivalent over the Docker API the task speaks, and a bare --user is
	# remapped to a subuid that cannot write the bind-mounted dashboard. Leaving
	# both empty there makes the container run as Podman's root, which already
	# maps back to the invoking user, so artifacts stay host-owned either way.
	_host_uid=""
	_host_gid=""
	if [ "$RUNTIME" = "docker" ]; then
		_host_uid="$(id -u)"
		_host_gid="$(id -g)"
	fi

	$RUNTIME run --rm -t ${_stdin:+"${_stdin}"} \
		--user "$(id -u):$(id -g)" \
		${_userns:+"${_userns}"} \
		${_sock_gid:+--group-add "${_sock_gid}"} \
		-v "${SOCKET}:/var/run/docker.sock" \
		-v "${VARS_FILE}:/playbook/vars.yaml:ro" \
		-v "${_creds_file}:/playbook/.creds.yml:ro,Z" \
		-v "${SCRIPT_DIR}:/playbook:Z" \
		-v "${REPO_ROOT}:/qa-infra:z" \
		${_dashboard_vol:+-v "${_dashboard_vol}"} \
		-e QA_INFRA_DIR=/qa-infra \
		-e HOST_DASHBOARD_DIR="${DASHBOARD_DIR:-${SCRIPT_DIR}/dashboard}" \
		-e HOST_UID="${_host_uid}" \
		-e HOST_GID="${_host_gid}" \
		-e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-}" \
		-e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-}" \
		-e HOME=/tmp \
		-e ANSIBLE_LOCAL_TEMP="/tmp/.ansible/tmp" \
		-e ANSIBLE_ASYNC_DIR="/tmp/.ansible_async" \
		"$IMAGE_NAME" \
		--extra-vars "@/playbook/.creds.yml" \
		${DASHBOARD_DIR:+--extra-vars dashboard_src=/external-dashboard} \
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

	# --userns=keep-id is Podman-only; on Docker we rely on --user alone
	_userns=""
	[ "$RUNTIME" = "podman" ] && _userns="--userns=keep-id"

	# Same stdin guard as run_playbook: keep the tty for live Cypress output,
	# bind stdin only when one is available.
	_stdin=""
	[ -t 0 ] && _stdin="-i"

	exec $RUNTIME run --rm -t ${_stdin:+"${_stdin}"} \
		--name "$_name" \
		--user "$(id -u):$(id -g)" \
		${_userns:+"${_userns}"} \
		--shm-size=2g \
		--env-file "${SCRIPT_DIR}/.env" \
		-e HOME=/tmp \
		-e KUBECONFIG=/root/.kube/config \
		-e NODE_PATH="" \
		-v "${DASHBOARD_DIR:-${SCRIPT_DIR}/dashboard}:/e2e" \
		-w /e2e \
		dashboard-test:0 ${SPEC:+--spec "${SPEC}"}
}

# --- Main ---
detect_runtime
detect_socket

# Parse commands: known verbs become tags, rest passes to ansible
TAGS=""
STREAM=""
_FORCE_BUILD=""
_BUILD_ONLY=""
_EXCL=""
DASHBOARD_DIR=""
SPEC=""

# destroy and build run on their own; refuse to mix them with stage verbs so a
# request like "provision destroy" can never silently drop or reorder stages.
_conflict() {
	echo "ERROR: '$1' cannot be combined with other commands." >&2
	echo "Run './run.sh --help' for usage." >&2
	exit 2
}
while [ $# -gt 0 ]; do
	case "$1" in
	provision | setup | test)
		[ -n "$_EXCL" ] && _conflict "$_EXCL"
		TAGS="${TAGS:+${TAGS},}$1"
		shift
		;;
	stream)
		[ -n "$_EXCL" ] && _conflict "$_EXCL"
		STREAM=1
		shift
		;;
	destroy)
		{ [ -n "$TAGS" ] || [ -n "$STREAM" ] || [ -n "$_EXCL" ]; } && _conflict destroy
		_EXCL=destroy
		TAGS="cleanup,never"
		shift
		;;
	build)
		{ [ -n "$TAGS" ] || [ -n "$STREAM" ] || [ -n "$_EXCL" ]; } && _conflict build
		_EXCL=build
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
	--dashboard-dir)
		if [ -z "${2:-}" ]; then
			echo "ERROR: --dashboard-dir requires a path argument." >&2
			exit 2
		fi
		if [ ! -d "${2}" ]; then
			echo "ERROR: --dashboard-dir path '$2' does not exist." >&2
			exit 2
		fi
		DASHBOARD_DIR="$(cd "${2}" && pwd)"
		shift 2
		;;
	--spec)
		if [ -z "${2:-}" ]; then
			echo "ERROR: --spec requires a spec path argument." >&2
			exit 2
		fi
		SPEC="${2}"
		shift 2
		;;
	-*)
		# Unknown flag: stop parsing and forward it (and the rest) to ansible.
		break
		;;
	*)
		echo "ERROR: unknown command '$1'." >&2
		echo "Run './run.sh --help' for usage." >&2
		exit 2
		;;
	esac
done

# --spec is only wired into the stream runner. The buffered ansible test stage
# runs the container without extra args, so refuse a silent full-suite run.
if [ -n "${SPEC}" ] && [ -z "${STREAM}" ]; then
	echo "ERROR: --spec requires the 'stream' command (e.g. ./run.sh stream test --spec <path>)." >&2
	exit 2
fi

# Validate --spec early when possible. The path is relative to the dashboard
# dir. Globs, comma lists, and not-yet-cloned checkouts are validated inside
# the container instead (cypress/jenkins/cypress.sh).
if [ -n "${SPEC}" ]; then
	case "${SPEC}" in
	/*)
		echo "ERROR: --spec must be relative to the dashboard dir, got absolute path '${SPEC}'." >&2
		exit 2
		;;
	*'*'* | *,*)
		: # glob or comma list — defer to in-container validation
		;;
	*)
		_dash_root="${DASHBOARD_DIR:-${SCRIPT_DIR}/dashboard}"
		if [ -d "${_dash_root}" ] && [ ! -f "${_dash_root}/${SPEC}" ]; then
			echo "ERROR: --spec path '${SPEC}' does not exist under ${_dash_root}." >&2
			exit 2
		fi
		;;
	esac
fi

# stream without explicit stages defaults to setup,test.
# When "provision" is requested (for example "stream provision"), the setup
# stage must also run because stream_cypress needs the runner image that setup
# builds. A bare "stream test" stays a fast reuse and is left untouched.
if [ -n "$STREAM" ]; then
	if [ -z "$TAGS" ]; then
		TAGS="setup,test"
	elif printf ',%s,' "$TAGS" | grep -q ',provision,' &&
		! printf ',%s,' "$TAGS" | grep -q ',setup,'; then
		TAGS="${TAGS},setup"
	fi
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
# Best-effort: artifacts from runs before the container was unprivileged may be
# root-owned; a failed chmod must not abort the run (set -e).
chmod -R u+rwX "${SCRIPT_DIR}/outputs" 2>/dev/null || true

if [ -n "${DASHBOARD_DIR:-}" ]; then
	echo "[run] Using local dashboard: ${DASHBOARD_DIR}"
	echo "[run] WARNING: --dashboard-dir overrides dashboard_repo and dashboard_branch (git clone skipped)."
	echo "[run] Ensure your local code is compatible with rancher_helm_repo and rancher_image_tag."
fi

echo "[run] Using ${RUNTIME} (socket: ${SOCKET})"
echo "[run] vars.yaml: ${VARS_FILE}"
echo ""

if [ -n "$STREAM" ]; then
	# Run everything except test via playbook, then stream Cypress directly
	run_playbook --skip-tags test ${TAGS:+--tags "${TAGS}"} "$@"
	stream_cypress
else
	run_playbook ${TAGS:+--tags "${TAGS}"} "$@"
fi
