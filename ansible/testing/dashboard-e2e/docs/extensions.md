# Testing a UI extension

The playbook was written for `rancher/dashboard`, but nothing in it is specific
to that repo. Point `dashboard_repo` somewhere else and the same pipeline
deploys a Rancher, clones the other repo, and runs its Cypress suite against it.
The Virtual Clusters (k3k) suite in `rancher/virtual-clusters-ui` is the first
user, and the
[`ui-vc-automation-matrix-job`](#the-jenkins-jobs) pair exists for it.

This page covers what changes when the repo under test is an extension rather
than the dashboard itself. Everything else — resolver, provisioning, Rancher
deploy, reporting — behaves exactly as described in
[architecture.md](architecture.md) and [resolver.md](resolver.md).

## The four variables

| Variable | Dashboard | An extension |
| --- | --- | --- |
| `dashboard_repo` | `rancher/dashboard` | `rancher/virtual-clusters-ui` |
| `dashboard_branch` | `master`, or derived from the Rancher under test | the repo's own branch, e.g. `main` |
| `e2e_spec_dirs` | unset | required: `cypress/e2e/tests/**/*.spec.ts` |
| `extension_version` | n/a | `published`, an exact version, or `dev-load` |

`dashboard_repo` still names the *test* repo, and `dashboard_branch` still names
its branch. The names are historical. The Jenkins `BRANCH` parameter is a
different thing again: it is the branch of `rancher/dashboard` that supplies the
`Jenkinsfile` and `init.sh`, and it stays on `master` regardless.

### `e2e_spec_dirs` is not optional here

Dashboard's specs live under `cypress/e2e/tests/<area>/`, and both
[`files/cypress.config.jenkins.ts`](../files/cypress.config.jenkins.ts) and
[`files/grep-filter.ts`](../files/grep-filter.ts) hardcode that layout. An
extension repo almost never matches it. Supplying `e2e_spec_dirs` (comma
separated globs) sets `E2E_SPEC_DIRS` in the container, which both files prefer
over their defaults. Leave it unset against an extension repo and the run finds
no specs and reports a vacuous pass.

### `extension_version`

Which build of the extension the specs install. The axis is **published versus
not published**, not GA versus rc.

| Value | Meaning |
| --- | --- |
| `published` (default) | the newest build in the chart repo, GA or rc. Both are installable from the Extensions UI, so both are in scope. |
| `<version>` | pin an exact published build, e.g. `1.3.0-rc1` or `1.2.1` |
| `dev-load` | build the extension from the checkout and register it as a developer load |

The value reaches the specs as `CYPRESS_extensionVersion`, written into `.env`
by the playbook. `published` and `<version>` are handled entirely by the specs:
the pipeline just passes the string through. `dev-load` is the only value the
pipeline itself acts on.

**`dev-load` is the only way to test code that is not published yet.** A spec
that depends on a new data-testid, or on a fix that is on `main` but in no
chart, cannot run against `published`. On `dev-load`,
[`files/cypress.sh`](../files/cypress.sh) runs the repo's own
`scripts/e2e-create-uiplugin.sh`, which builds the extension, serves it over
`127.0.0.1`, and registers it with Rancher. That endpoint is reachable because
the browser runs in the same container.

## What the pipeline does differently

Three behaviours are gated on the repo actually being the dashboard, so they
switch themselves off for an extension.

**The checkout shape.** `cypress.sh` looks for `cypress/package.json` first
(dashboard keeps `cypress/` as its own workspace) and falls back to a root
`package.json` that declares `cypress` (what extension repos have). It installs
in whichever it finds. A checkout matching neither is rejected up front rather
than failing later with a confusing yarn error.

**The dependency-manifest overlay is skipped.** On a dashboard release branch
the playbook overlays five dependency files from `master` so an old branch does
not pin an ancient Cypress. An extension repo has one branch serving every
supported Rancher, so there is nothing to overlay and the task is gated on
`dashboard_repo` ending in `/dashboard`. See
[ci-files.md](ci-files.md).

## The Jenkins jobs

The Virtual Clusters jobs are defined in
[`rancherlabs/jenkins-job-builder`](https://github.com/rancherlabs/jenkins-job-builder)
as `ui-vc-tests-matrix.yml`. They mirror the dashboard jobs one for one; the
whole pipeline shape in [jenkins.md](jenkins.md) applies unchanged.

| Job | Role |
| --- | --- |
| `ui-vc-automation-matrix-multi-job` | parent. Start here. Fans out one child build per `TEST_MATRIX` row per `CYPRESS_TAGS` set |
| `ui-vc-automation-matrix-job` | child. One Rancher, one AWS cluster, one Cypress run |

Both take their pipeline definition from `rancher/dashboard`
(`cypress/jenkins/Jenkinsfile_multi` and `cypress/jenkins/Jenkinsfile`) and
their specs from `rancher/virtual-clusters-ui`. Only the `VARS_YAML_CONFIG`
defaults differ from the dashboard jobs:

```yaml
dashboard_repo: "rancher/virtual-clusters-ui"
dashboard_branch: "main"
e2e_spec_dirs: "cypress/e2e/tests/**/*.spec.ts"
extension_version: "published"
cypress_tags: "@adminUser+@jenkins"
```

Two constraints on the matrix:

- **Every row must be a `prime` kind.** The extension is Prime-only and needs
  Rancher 2.13 or newer. A community row installs a Rancher where the extension
  never appears in the UI.
- **Pin the k3s version on every row.** Only `metadata:` rows read
  `e2e.kube.version` from `branches-metadata.json`; an unpinned row silently
  falls back to the base config.

The `@jenkins` tag exists because these specs provision real infrastructure and
are not meant to run in a developer's ad-hoc suite.

## Running one locally

### Before you begin

You need:

- A **Rancher Prime** instance. The spec asserts this up front
  via `/rancherversion`, so a community Rancher fails immediately rather than
  timing out on a card that was never going to render.
- **AWS credentials.** The spec provisions a three-node RKE2 cluster on EC2 to
  host the virtual clusters, installs k3k onto it, and tears it all down
  afterwards. Without credentials the cloud credential is created empty and the
  cluster never comes up.
- **Node 24** and **yarn**.

### 1. Clone and install

```bash
git clone https://github.com/rancher/virtual-clusters-ui.git
cd virtual-clusters-ui
yarn install --frozen-lockfile
```

### 2. Export the environment

```bash
# Rancher under test. TEST_BASE_URL is the dashboard URL; the API URL and the
# Cypress baseUrl are both derived from it.
export TEST_BASE_URL="https://<rancher>/dashboard"
export TEST_USERNAME="admin"
export TEST_PASSWORD="<pw>"

# Required: the spec provisions an EC2 host cluster.
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
```

### 3. Run

<details>
<summary><strong>Against a published build</strong></summary>

Pick the spec from the runner UI:

```bash
CYPRESS_extensionVersion=1.3.0-rc1 yarn cy:open
```

Or headless:

```bash
CYPRESS_extensionVersion=1.3.0-rc1 \
  yarn cy:run --spec cypress/e2e/tests/pages/extensions/virtual-clusters/virtual-clusters-extension.spec.ts
```

Leave `CYPRESS_extensionVersion` unset to take the newest published build.

</details>

<details>
<summary><strong>Against unpublished code (developer load)</strong></summary>

Do by hand what `cypress.sh` does in the container — register the developer
load first, then point Cypress at it:

```bash
bash scripts/e2e-create-uiplugin.sh

CYPRESS_extensionVersion=dev-load \
  yarn cy:run --spec cypress/e2e/tests/pages/extensions/virtual-clusters/virtual-clusters-extension.spec.ts
```

The script reuses `TEST_BASE_URL` and `TEST_PASSWORD` from step 2, stripping a
trailing `/dashboard` to reach the Rancher API. It builds the extension, serves
it on port 8080, and registers it over the Steve API.

**`CYPRESS_extensionVersion=dev-load` on the second command is not optional.**
The spec reads it too: on `dev-load` it skips adding the chart repo, skips the
install, and skips the uninstall test, because a developer load is already
present and there is no chart to remove. Omit it and the spec defaults to
`published` and installs the chart on top of the dev load.

</details>

### 4. Clean up after a developer load

Two things are left behind, neither of which the spec cleans up:

| Left behind | Why | Remove it |
| --- | --- | --- |
| The `serve-pkgs` process on port 8080 | The browser fetches the bundle from it for the whole run | Stop the process; it logs to `serve-pkgs.log` |
| The developer-loaded `UIPlugin` | Named `virtual-clusters-<version>`, not the `virtual-clusters` a catalog install creates, so the spec's cleanup never matches it | `kubectl delete uiplugin -n cattle-ui-plugin-system virtual-clusters-<version>` |
