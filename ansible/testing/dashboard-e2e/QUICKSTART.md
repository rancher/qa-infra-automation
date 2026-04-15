# Quickstart

Run Dashboard Cypress E2E tests with just Docker and a config file.
Choose your scenario below and follow the numbered steps.

> **Full pipeline docs** (provision + deploy + test) are in
> the [README](README.md).

---

## Before you begin

You need:

- **Docker** or **Podman** — installed and running
- **git**
- **Windows only:** a
  [WSL2](https://learn.microsoft.com/en-us/windows/wsl/install) terminal

If you plan to test against an existing Rancher, have the FQDN and
admin password ready.

---

## 1 — Clone the repo

```bash
git clone https://github.com/rancher/qa-infra-automation.git
cd qa-infra-automation/ansible/testing/dashboard-e2e
```

---

## 2 — Create your config

```bash
cp vars.yaml.example vars.yaml
$EDITOR vars.yaml
```

<details>
<summary><strong>Minimal config — existing Rancher</strong></summary>

Use this when you already have a Rancher instance running:

```yaml
job_type: "existing"
create_initial_clusters: false

rancher_host: "rancher.example.com"      # FQDN, no https://
rancher_password: "your-admin-password"

rancher_helm_repo: "rancher-com-rc"
rancher_image_tag: "v2.14-head"          # must match your Rancher
cypress_tags: "@generic"

dashboard_repo: "rancher/dashboard"
dashboard_branch: "master"
```

</details>

<details>
<summary><strong>Minimal config — provision new infra</strong></summary>

Use this to spin up a fresh AWS cluster with Rancher:

```yaml
job_type: "recurring"

rancher_helm_repo: "rancher-com-rc"
rancher_image_tag: "v2.14-head"
cypress_tags: "@adminUser"

dashboard_repo: "rancher/dashboard"
dashboard_branch: "master"
```

Export AWS credentials before running:

```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
```

</details>

See [`vars.yaml.example`](vars.yaml.example) for all available options. Chart-related runs can use `allow_filtered_catalog_skip` (see the Cypress section in the [README](README.md#cypress-test-runner)).

---

## 3 — Run

### Existing Rancher

```bash
./run.sh stream
```

### Provision + test (full pipeline)

```bash
./run.sh stream provision
```

> The first run builds the runner image (~2 min). Subsequent runs
> reuse the cached image.
>
> `stream` gives you **real-time Cypress output with colors**.
> Without it (e.g. `./run.sh setup test`), Ansible buffers output
> until the task completes.

---

## 4 — Iterate

The most common workflow is to set up once, then re-run tests as you
tweak `cypress_tags` or dashboard code.

| What changed | Command |
| --- | --- |
| Only `cypress_tags` in `vars.yaml` | `./run.sh stream test` |
| `allow_filtered_catalog_skip` or other vars that affect `.env` | `./run.sh stream setup test` |
| Dashboard source code | `./run.sh stream` |
| Force-rebuild the runner image | `./run.sh build` then `./run.sh stream test` |

### Example: iterate on a provisioned cluster

```bash
# 1. Provision + first test run
./run.sh stream provision

# 2. Change cypress_tags in vars.yaml, re-run (seconds to start)
./run.sh stream test

# 3. Fix a test, re-clone dashboard + rebuild, test again
./run.sh stream

# 4. Tear down AWS infra when done
./run.sh destroy
```

---

## 5 — Check results

```bash
# JUnit XML
ls dashboard/results.xml

# HTML report with screenshots
ls dashboard/cypress/reports/html/
```

Open the report:

```bash
open dashboard/cypress/reports/html/index.html 2>/dev/null || \
  xdg-open dashboard/cypress/reports/html/index.html
```

---

## Command reference

```bash
./run.sh                               # full pipeline (all stages + cleanup)
./run.sh provision                     # provision infra only
./run.sh setup                         # clone repo + build test image
./run.sh test                          # re-run tests only (buffered output)
./run.sh setup test                    # setup + test (most common)
./run.sh provision setup test          # everything except cleanup
./run.sh stream                        # setup + test, live Cypress output
./run.sh stream provision              # provision + setup + test, live output
./run.sh stream test                   # re-run tests, live output
./run.sh destroy                       # tear down infrastructure
./run.sh build                         # rebuild the runner image
./run.sh test -v                       # verbose, buffered output
./run.sh -h                            # show all commands
```

---

## Cypress tag examples

| Tags | What they test |
| --- | --- |
| `@generic` | Login, home, about — no clusters needed |
| `@adminUser` | Admin workflows — needs default Rancher setup |
| `@standardUser` | Standard-user permissions |
| `@adminUser+@vai` | Multiple tags combined |
| `@bypass+@generic` | Skip auto-filtering (`+-@prime`/`+-@noVai`) |

---

## Optional credentials

Export these **before** `./run.sh` when needed:

| Variable | Purpose |
| --- | --- |
| `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` | Provision EC2 instances |
| `QASE_TOKEN` | Report results to Qase |
| `PERCY_TOKEN` | Visual regression with Percy |
| `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` / `AZURE_AKS_SUBSCRIPTION_ID` | AKS clusters |
| `GKE_SERVICE_ACCOUNT` | GKE clusters |

---

## Running Ansible directly (without Docker)

Use this path if you need to develop or debug the playbook itself.

### Extra prerequisites

- `git`, `xxd`
- Python 3.8+
- Ansible core < 2.17

### Install Ansible

**Ubuntu / Debian:**

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source $HOME/.local/bin/env
uv tool install "ansible-core<2.17" --with ansible
```

**macOS:**

```bash
brew install uv
uv tool install "ansible-core<2.17" --with ansible
```

> Or with pip: `pip install "ansible-core<2.17" ansible`

Install the required collections:

```bash
ansible-galaxy collection install \
  cloud.terraform kubernetes.core \
  "community.docker:<5" "community.crypto:<3" --upgrade
```

### Run the playbook

```bash
# Setup + test against existing Rancher
ansible-playbook dashboard-e2e-playbook.yml --tags setup,test

# Setup only (build image, skip test run)
ansible-playbook dashboard-e2e-playbook.yml --tags setup

# Re-run tests only
ansible-playbook dashboard-e2e-playbook.yml --tags test
```

For real-time Cypress output with colors, run Docker manually
after setup:

```bash
docker run --rm -t \
  --shm-size=2g \
  --env-file .env \
  -e NODE_PATH="" \
  -v "$PWD/dashboard:/e2e" \
  -w /e2e \
  dashboard-test:latest
```

---

## Next steps

- **Full pipeline configuration:** See the [README](README.md)
  for AWS, Helm repo, and `job_type: "recurring"` options.
- **Helm repo types:** See *Helm Repos and Image Resolution*
  in the README for all 6 repo types with examples.
- **Jenkins CI:** The `cypress/jenkins/init.sh` script in the
  dashboard repo wraps this playbook for automated runs.
