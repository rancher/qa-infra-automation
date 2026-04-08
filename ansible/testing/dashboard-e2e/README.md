# Dashboard E2E Test Pipeline

Ansible playbook that orchestrates the full Rancher Dashboard Cypress end-to-end
test pipeline. It provisions AWS infrastructure, deploys Rancher on K3s, runs
Cypress tests inside a Docker container, and tears everything down afterward.

## What It Does

```text
1. Provision    AWS EC2 instances via OpenTofu (rancher HA cluster, import cluster, custom node)
2. Deploy       K3s on each cluster, then Rancher via Helm on the HA cluster
3. Setup        Clone dashboard repo, configure Rancher (users, roles), build Docker image
4. Test         Run Cypress specs inside Docker against the live Rancher instance
5. Cleanup      Destroy all AWS resources (EC2, Route53 records, security groups)
```

Each phase is controlled by Ansible tags so you can run them independently.

## Prerequisites

The following must be available on the machine running the playbook:

| Tool | Ubuntu/Debian | macOS | Notes |
|------|--------------|-------|-------|
| Ansible >= 2.16 | `uv tool install "ansible-core<2.17" --with ansible` | `brew install uv && uv tool install "ansible-core<2.17" --with ansible` | [Install uv](https://docs.astral.sh/uv/getting-started/installation/) first, or use `pip` |
| OpenTofu >= 1.11 | [opentofu.org/docs/intro/install](https://opentofu.org/docs/intro/install/) | `brew install opentofu` | Only needed for provisioning (`--tags provision`) |
| Docker or Podman | `sudo apt-get install docker.io` | [Docker Desktop](https://docs.docker.com/desktop/install/mac-install/) | For building and running the Cypress test image |
| Helm 3 | [helm.sh/docs/intro/install](https://helm.sh/docs/intro/install/) | `brew install helm` | Used for version resolution in provision and setup |
| curl, git, xxd | `sudo apt-get install curl git xxd` | curl, git, xxd are built-in | `xxd` is used for random prefix generation |

Required Ansible collections (installed automatically by `init.sh` in Jenkins):

```bash
ansible-galaxy collection install \
  cloud.terraform kubernetes.core "community.docker:<5" "community.crypto:<3" --upgrade
```

## Quick Start

```bash
cd ansible/testing/dashboard-e2e

# 1. Copy and edit variables
cp vars.yaml.example vars.yaml
# Edit vars.yaml  --  at minimum you need to set the AWS variables

# 2. Export AWS credentials (secrets — don't put these in vars.yaml)
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."

# 3. Run the full pipeline
ansible-playbook dashboard-e2e-playbook.yml

# Or use the containerized wrapper (Docker/Podman only prerequisite):
./run.sh
```

## Usage Examples

### Containerized wrapper (run.sh)

The `run.sh` wrapper runs everything inside a container — the only prerequisite
is Docker or Podman. Commands are simple verbs that can be combined:

```bash
# Full pipeline (provision → setup → test → cleanup)
./run.sh

# Provision + setup + test with live Cypress output
./run.sh stream provision

# Setup + test (most common — iterate on provisioned infra)
./run.sh stream

# Re-run tests only (after changing cypress_tags)
./run.sh stream test

# Provision + setup (no test)
./run.sh provision setup

# Setup + test (buffered output)
./run.sh setup test

# Destroy infrastructure
./run.sh destroy

# Rebuild the runner image
./run.sh build

# Pass extra ansible flags
./run.sh test -v          # verbose
./run.sh test --check     # dry-run
```

### Direct Ansible (without container)

Use these when running Ansible directly on the host:

```bash
# Full pipeline
ansible-playbook dashboard-e2e-playbook.yml --tags provision,setup,test

# Provision only (long-lived environment)
ansible-playbook dashboard-e2e-playbook.yml --tags provision

# Setup + test (against provisioned infra)
ansible-playbook dashboard-e2e-playbook.yml --tags setup,test

# Re-run tests only
ansible-playbook dashboard-e2e-playbook.yml --tags test

# Cleanup
ansible-playbook dashboard-e2e-playbook.yml --tags cleanup,never
```

### Iterate on provisioned infrastructure

After a full provision run, you can re-run setup and tests
against the same infrastructure without reprovisioning:

```bash
# Provision + first test run (live Cypress output)
./run.sh stream provision

# Change tags, branch, or other settings in vars.yaml, then:
./run.sh stream

# Or just re-run tests with the existing Docker image:
./run.sh stream test

# When done, tear down:
./run.sh destroy
```

Or with direct Ansible:

```bash
ansible-playbook dashboard-e2e-playbook.yml --tags setup,test
ansible-playbook dashboard-e2e-playbook.yml --tags test
ansible-playbook dashboard-e2e-playbook.yml --tags cleanup,never
```

### Real-time Docker streaming

The `stream` command in `run.sh` handles this automatically. For direct Ansible
usage, run setup only, then Docker manually:

```bash
# Setup: clone dashboard, build image, generate .env
ansible-playbook dashboard-e2e-playbook.yml --tags setup

# Run Cypress with real-time streaming
docker run --rm -t \
  --shm-size=2g \
  --env-file .env \
  -e NODE_PATH="" \
  -v "$PWD/dashboard:/e2e" \
  -w /e2e \
  dashboard-test:latest
```

### Test only (against existing Rancher)

Skip provisioning and run tests against an already-deployed Rancher instance.
You must set `rancher_host` to your Rancher URL and `job_type` to `existing`.

```bash
# With run.sh
./run.sh stream

# Or with direct Ansible
ansible-playbook dashboard-e2e-playbook.yml \
  --extra-vars "job_type=existing rancher_host=rancher.example.com" \
  --tags setup,test
```

### Cleanup only (destroy infrastructure)

Tear down all AWS resources (EC2, Route53) created during provisioning.

```bash
# With run.sh
./run.sh destroy

# Or with direct Ansible (requires both tags — 'never' prevents accidental execution)
ansible-playbook dashboard-e2e-playbook.yml --tags cleanup,never
```

### Jenkins integration

The [`cypress/jenkins/init.sh`](https://github.com/rancher/dashboard/blob/master/cypress/jenkins/init.sh)
script in the [rancher/dashboard](https://github.com/rancher/dashboard) repository
wraps this playbook. It handles prerequisite installation, variable generation
from Jenkins environment variables, and real-time Cypress streaming.

```bash
# Full run (called by Jenkinsfile)
cypress/jenkins/init.sh

# Destroy only (called by Jenkinsfile finally block)
cypress/jenkins/init.sh destroy
```

Jenkins uses `--skip-tags test` so that Cypress output streams directly to
the Jenkins console with color support via init.sh's Docker run.

## Configuration

Variables are loaded from `vars.yaml` (copy from `vars.yaml.example`). When
running from Jenkins, `init.sh` generates this file automatically from
environment variables.

### AWS infrastructure

| Variable | Default | Description |
|----------|---------|-------------|
| `aws_region` | `us-west-1` | AWS region for all resources |
| `aws_instance_type` | `t3a.xlarge` | EC2 instance type |
| `aws_volume_size` | `60` | Root volume size in GB |
| `server_count` | `3` | Number of Rancher HA nodes (1 or 3) |

The following are **required** and have no defaults. Export them as environment
variables — don't put secrets in `vars.yaml`:

- `AWS_ACCESS_KEY_ID` — AWS credentials
- `AWS_SECRET_ACCESS_KEY` — AWS credentials

The remaining AWS settings go in `vars.yaml`:
`aws_ami`, `aws_route53_zone`, `aws_vpc`, `aws_subnet`, `aws_security_group`

### Rancher

| Variable | Default | Description |
|----------|---------|-------------|
| `rancher_helm_repo` | `rancher-com-rc` | Helm repo name (see "Helm Repos and Image Resolution" below) |
| `rancher_image_tag` | `v2.14-head` | Rancher image tag. Controls target branch: `v2.14-head` -> `release-2.14`, `head` -> `master` |
| `k3s_kubernetes_version` | `v1.30.0+k3s1` | K3s version for all clusters |
| `bootstrap_password` | `password` | Rancher first-boot password |
| `rancher_password` | `password1234` | Permanent admin password set after bootstrap |

### Helm Repos and Image Resolution

Rancher is released through two pipelines: **Prime** (SUSE registry) and
**Community** (Docker Hub). Each pipeline has production, RC, and alpha stages.

Each repo is self-contained — chart and image are resolved from the same source.
For Prime staging repos (`rancher-latest`, `rancher-alpha`), the resolved chart
version becomes the image tag (e.g. `2.14.0-alpha13` → `v2.14.0-alpha13`).

| `rancher_helm_repo` | Chart source | Image registry | Image tag |
|---------------------|-------------|----------------|-----------|
| `rancher-prime` | charts.rancher.com/.../prime | `registry.suse.com` | `v{chart_version}` |
| `rancher-latest` | charts.optimus.rancher.io/.../latest | `stgregistry.suse.com` | `v{highest -rc match}` |
| `rancher-alpha` | charts.optimus.rancher.io/.../alpha | `stgregistry.suse.com` | `v{highest -alpha match}` |
| `rancher-community` | releases.rancher.com/.../stable | Docker Hub | `rancher_image_tag` as-is |
| `rancher-com-rc` | releases.rancher.com/.../latest | Docker Hub | `rancher_image_tag` as-is |
| `rancher-com-alpha` | releases.rancher.com/.../alpha | Docker Hub | `rancher_image_tag` as-is |

### Examples

```yaml
# Prime stable — released 2.13.4
rancher_helm_repo: "rancher-prime"
rancher_image_tag: "v2.13.4"
# → chart 2.13.4 from rancher-prime, image registry.suse.com/rancher/rancher:v2.13.4

# Prime RC — test the latest 2.13 release candidate
rancher_helm_repo: "rancher-latest"
rancher_image_tag: "v2.13"
# → highest 2.13.x-rc from optimus/latest, image stgregistry.suse.com/rancher/rancher:v2.13.4-rc1

# Prime alpha — test the next minor
rancher_helm_repo: "rancher-alpha"
rancher_image_tag: "v2.14"
# → highest 2.14.x-alpha from optimus/alpha, image stgregistry.suse.com/rancher/rancher:v2.14.0-alpha13

# Community GA — stable community release
rancher_helm_repo: "rancher-community"
rancher_image_tag: "v2.13.3"
# → chart 2.13.3 from releases.rancher.com/stable, image rancher/rancher:v2.13.3

# Community RC (default) — test upcoming community release
rancher_helm_repo: "rancher-com-rc"
rancher_image_tag: "v2.14-head"
# → latest 2.14.x chart from releases.rancher.com/latest, image rancher/rancher:v2.14-head

# Community alpha
rancher_helm_repo: "rancher-com-alpha"
rancher_image_tag: "v2.14.0-alpha9"
# → chart 2.14.0-alpha9 from releases.rancher.com/alpha, image rancher/rancher:v2.14.0-alpha9

# Dev head — latest from any repo
rancher_helm_repo: "rancher-com-rc"
rancher_image_tag: "head"
# → latest chart in the repo, image rancher/rancher:head
```

### Cypress test runner

| Variable | Default | Description |
|----------|---------|-------------|
| `cypress_tags` | `@adminUser` | Cypress grep tags to run (e.g. `@userMenu`, `@adminUser+@components`) |
| `allow_filtered_catalog_skip` | `true` | When `true`, chart tests may skip if the chart is filtered out of the UI catalog. Set to `false` to fail instead. |
| `job_type` | `recurring` | `recurring` provisions new infra; `existing` skips provisioning |
| `create_initial_clusters` | `true` | Whether to create import cluster and custom node. In `existing` mode, provisions only these resources (not the Rancher server) |
| `dashboard_repo` | `rancher/dashboard` | Dashboard GitHub repo to clone |
| `dashboard_branch` | (auto-detected) | Branch to clone. Auto-detected from `rancher_image_tag` (e.g. `v2.14-head` → `release-2.14`) |
| `dashboard_overlay_branch` | `master` | Branch to overlay dependency files from (package.json, yarn.lock, cypress.config.ts). CI files come from the playbook's `files/` directory |

### Pinned versions

These are kept in sync with the
[Cypress Docker factory](https://github.com/cypress-io/cypress-docker-images/blob/master/factory/.env).
Only change them if the factory updates.

| Tool | Default | Source |
|------|---------|--------|
| Chrome | `146.0.7680.164-1` | Factory `.env` |
| Node.js | `24.14.0` | Factory `.env` |
| Yarn | `1.22.22` | Factory `.env` |
| Cypress | `11.1.0` | Dashboard `package.json` |

## Cypress Tag System

The playbook automatically adjusts Cypress tags before running tests. This
mirrors the logic in the upstream dashboard `init.sh`:

- **Non-prime repos** (e.g. `rancher-com-rc`, `rancher-stable`): Appends
  `+-@prime` to exclude prime-only tests.
- **Prime repos** (`rancher-prime`, `rancher-latest`, `rancher-alpha`): Appends
  `+-@noPrime` to exclude non-prime tests.
- **Always**: Appends `+-@noVai` to exclude VAI-specific tests.
- **Bypass**: If `@bypass` is present in the tags, no automatic exclusions are
  added. Use this when you want full control over which tests run.

Example: Input `@userMenu` with repo `rancher-com-rc` becomes
`@userMenu+-@prime+-@noVai`.

## Tags

| Tag | What it runs |
|-----|-------------|
| `provision` | Infrastructure provisioning (OpenTofu) + K3s + Rancher deploy + Helm resolution |
| `setup` | Clone dashboard, copy CI files, build Docker image, generate .env |
| `test` | Cypress Docker run + result collection |
| `cleanup` | Infrastructure teardown (requires `--tags cleanup,never`) |

Pre-tasks (validation, tag adjustment) use `always` with conditional guards —
they are evaluated on every run but skip work that doesn't apply (e.g. Cypress
tag adjustment is skipped during `cleanup`, host validation is skipped when
`provision` will create it).

## Outputs

After a successful run, the following artifacts are available:

| Path | Description |
|------|-------------|
| `dashboard/results.xml` | JUnit XML test results |
| `dashboard/cypress/reports/html/` | Mochawesome HTML report with screenshots |
| `notification_values.txt` | Rancher version info for Slack notifications |
| `outputs/` | SSH keys, kubeconfigs, tfvars (cleaned up on destroy) |

## Architecture

```text
dashboard-e2e-playbook.yml          Main orchestrator
  pre_tasks: [always] (with conditional guards)
    validate AWS vars                 Skipped for non-recurring jobs
    recover rancher_host / ssh_key    Skipped during cleanup
    validate rancher_host             Skipped when provision will create it
    adjust Cypress tags               Skipped during cleanup/provision-only
  tasks:
    tasks/provision.yml       [provision]  OpenTofu apply (3 workspaces in parallel via async)
    tasks/resolve-helm-version.yml  [provision, setup]  Resolve Rancher Helm chart version
    tasks/install-k3s-rancher.yml   [provision]  K3s + rancher-ha playbooks (parallel)
    tasks/setup-test-env.yml  [setup]    Clone repo, CI files, user setup (role), Docker build
    tasks/run-tests.yml       [test]     Docker run, collect JUnit + HTML reports
    tasks/cleanup.yml         [cleanup]  OpenTofu destroy (loop), remove artifacts

files/                               CI files (copied into dashboard clone at setup)
  Dockerfile.ci                      Cypress factory image + kubectl
  cypress.sh                         Container entrypoint — runs Cypress + jrm
  cypress.config.jenkins.ts          Cypress config (reporters, retries, Qase)
  grep-filter.ts                     Pre-filter specs by tag
  utils.sh                           Shared shell utilities (clean_tags, etc.)
```

### Key Scripts and Tasks

- **`files/`** — CI files that are infrastructure concern, not test code.
  The playbook copies them into the dashboard clone during setup, making the
  playbook fully self-contained. No git overlay needed for CI files.
- **`rancher_user_setup` role** (`ansible/roles/rancher_user_setup/`) — Creates
  Rancher local users with global and project role bindings via the Rancher API.
  Parameterized: accepts a list of users, roles, and project bindings. Idempotent
  (skips if resources already exist). Error handling configurable (`fail` or `warn`).
- **`files/grep-filter.ts`** — Pre-filters Cypress spec files by tag before
  Cypress launches. Runs inside the Docker container to reduce unnecessary
  spec loading.

## Troubleshooting

### OpenTofu init fails with "Failed to install provider"

Transient GitHub rate limit. Re-run the pipeline -- it will retry automatically.

### K3s fails to start

Check the K3s version compatibility with your AMI. The default `v1.30.0+k3s1`
works with Ubuntu 22.04/24.04 AMIs. If using a newer AMI, you may need a newer
K3s version.

### Rancher setup returns 401 Unauthorized

The playbook changes the admin password from `bootstrap_password` to
`rancher_password` during deploy. Make sure `rancher_password` in vars.yaml
matches what you expect. The `rancher_user_setup` role uses `rancher_password`.

### Cypress tests fail with "baseUrl not reachable"

The Rancher UI may not be ready yet. The playbook waits up to 5 minutes for
`/dashboard/auth/login` to return 200. If your Rancher is slow to start,
increase the `retries` value in `setup-test-env.yml`.

### Cleanup fails with "workspace not found"

This is safe to ignore. The cleanup uses `|| exit 0` so missing workspaces
(e.g. if provisioning was skipped) do not cause failures.

### `xxd: command not found`

The playbook uses `xxd` to generate random resource prefixes. It ships with
macOS and most Linux distros. On minimal systems: `apt-get install xxd`.

### Shell compatibility

All shell tasks in the playbook are POSIX-compatible (`/bin/sh`). No `/bin/bash`
dependency — the playbook runs on any system with a POSIX shell.

## Dependencies

Ansible collections required (install manually or let `init.sh` handle it in Jenkins):

- `cloud.terraform` — OpenTofu/Terraform state lookups and provider management
- `kubernetes.core` — Kubernetes resource operations
- `community.docker` **< 5** — Docker image build and container
  management (v5+ requires ansible-core ≥ 2.17)
- `community.crypto` **< 3** — SSH keypair generation
  (v3+ requires ansible-core ≥ 2.17)
