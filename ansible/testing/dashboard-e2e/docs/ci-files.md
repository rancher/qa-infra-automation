# `files/` and the dashboard checkout

The playbook clones `rancher/dashboard` and then overwrites five files inside
it. This page explains what those files are, why they live here instead of
there, and what else happens to the checkout before Cypress sees it.

## Two checkouts, not one

A Jenkins build clones `rancher/dashboard` twice, for two different reasons.

| Checkout | Made by | Branch | Used for |
| --- | --- | --- | --- |
| `$WORKSPACE` | The Jenkins `Checkout` stage | `BRANCH` | The pipeline's own scripts: `Jenkinsfile`, `init.sh`, `slack-notification.sh`, `disk-report.sh` |
| `$PLAYBOOK_DIR/dashboard` | `tasks/setup-test-env.yml` | Matched to the Rancher under test | The tests themselves |

Only the second one is the code under test. Its branch is derived from the
Rancher being deployed:

```text
dashboard_branch set and not 'master'  →  that branch
rancher_image_tag == 'head'            →  master
rancher_image_tag matches ^v?<X>.<Y>   →  release-<X>.<Y>
otherwise                              →  dashboard_branch, default master
```

The `v` is optional on purpose. A hand written row spells the tag `v2.15.1-rc2`,
but a `channel_source: prime` row takes its tag from the chart index, where
versions are bare (`2.15.1-rc2`). Matching only the `v` form sent every Prime
row to `master`, so a 2.15 server was tested with the next minor's specs and
failed on differences that were never regressions.

`dashboard_src` overrides all of this with a local path, which is how you test
uncommitted changes. The clone is then skipped entirely.

## The CI overlay

Straight after the clone, five files are copied from [`files/`](../files) over
the checkout's own `cypress/jenkins/` directory:

| Source | Destination in the checkout |
| --- | --- |
| `files/Dockerfile.ci` | `cypress/jenkins/Dockerfile.ci` |
| `files/cypress.sh` | `cypress/jenkins/cypress.sh` (0755) |
| `files/utils.sh` | `cypress/jenkins/utils.sh` (0755) |
| `files/grep-filter.ts` | `cypress/jenkins/grep-filter.ts` |
| `files/cypress.config.jenkins.ts` | `cypress/jenkins/cypress.config.jenkins.ts` |

`rancher/dashboard` carries its own copies of all five at the same paths. **The
copies here win.** A release branch's versions may be months old, and these are
an infrastructure concern rather than test code: how the container is built, how
tags are filtered, how reports are merged. Keeping them here means the pipeline
can be fixed for every branch at once, without backporting to each one, and
without a git overlay for CI files.

The consequence to remember when debugging: **editing
`cypress/jenkins/cypress.sh` in the dashboard repo has no effect on a run.**
Edit `files/cypress.sh` here.

The files that are *not* overwritten (`Jenkinsfile`, `Jenkinsfile_multi`,
`init.sh`, `slack-notification.sh`, `disk-report.sh`) are read from the first
checkout, by Jenkins, before the playbook exists. Those must be changed in
`rancher/dashboard`.

## What each file does

### `Dockerfile.ci`

Builds `dashboard-test:<executor>` on top of `cypress/factory`, pinned by
digest. It adds four things and nothing else:

- **kubectl**, checksummed per architecture, for the imported-cluster tests
- **curl**, which the imported-cluster registration command shells out to
- **`imported_config`** copied to `/root/.kube/config` at mode 644, because a
  local run starts the container with `--user` and that non-root user has to
  read it
- **corepack**, pinned, so Berry branches can run `yarn@4`

Its entrypoint is `bash cypress/jenkins/cypress.sh`, a path *inside the bind
mount*, not inside the image. The image is a toolchain; the code comes from the
checkout at run time. That is why a source change needs no rebuild.

The build context is `outputs/docker-context`, a directory containing only
`imported_config`, not the checkout. Building from the checkout would ship the
whole working tree including `cypress/node_modules`, and would need a
`.dockerignore` written into a directory that is not ours to edit.

`Dockerfile.ci` is asserted to be free of BuildKit-only syntax before the build,
because Jenkins agents use the legacy builder. `COPY --chmod` is the specific
trap; the mode is set in a separate `RUN` instead.

### `cypress.sh`

The container entrypoint, and the whole test run:

1. Install dependencies from `cypress/yarn.lock`, choosing classic Yarn or
   Berry-via-corepack from what the checkout pins.
2. Normalise the tag expression (`utils.sh`, `clean_tags`).
3. Pre-filter specs with `grep-filter.ts` and pass the result as `--spec`.
4. `cypress run --config-file cypress/jenkins/cypress.config.jenkins.ts`,
   wrapped in `percy exec` when Percy is enabled.
5. Merge the per-spec JUnit files into `results.xml` with `jrm`.

It contains the literal token `CYPRESSTAGS`, which the playbook substitutes with
the resolved `cypress_tags` before the build. That token is the fallback when
`CYPRESS_grepTags` is not in the environment.

### `grep-filter.ts`

Reads `CYPRESS_grepTags`, globs the spec directories, parses each file's test
names with `find-test-names`, and prints the comma-separated list of specs that
contain at least one matching test.

It exists because Cypress ignores `specPattern` changes made in
`setupNodeEvents`, so the filtering has to happen before Cypress starts. Without
it every spec is loaded and then mostly skipped, which is slow and noisy. A spec
that fails to parse is included rather than dropped.

### `cypress.config.jenkins.ts`

The Cypress config used in CI: spec directories, reporters
(`cypress-multi-reporters` into `mocha-junit-reporter` and
`cypress-mochawesome-reporter`), retries, and the Qase integration. The viewport
is not set here; it comes from `CYPRESS_VIEWPORT_*` in `.env`.

### `utils.sh`

One function, `clean_tags`: strips `@bypass`, turns spaces into `+`, collapses
repeated `+`, trims the ends. Sourced by `cypress.sh`.

## The dependency overlay

Older release branches have no `cypress/package.json` of their own. A run
against one still needs a module tree, so five files are overlaid from a newer
branch:

```text
cypress/package.json  cypress/yarn.lock  package.json  yarn.lock  cypress.config.ts
```

plus `cypress/support/qase.ts` when the source branch has it.

The source is chosen rather than fixed. The target's *root* manifest names the
Cypress major it was written against; the next three minor release branches are
probed, and the first that pins the same major wins. That is the nearest newer
branch, the one whose spec set has drifted least. `master` is the fallback, and
`dashboard_overlay_branch` overrides the search entirely.

The overlay is a partial `git checkout FETCH_HEAD -- <paths>`, so the rest of
the target branch is untouched. This is one of the few places the playbook uses
`command` instead of a module: `ansible.builtin.git` checks out a whole tree.

### The `@cypress/grep` adaptation

Release branches register grep with a default import from a deep path:

```ts
import registerCypressGrep from '@cypress/grep/src/support'
registerCypressGrep()
```

`@cypress/grep` v5 moved to `dist/` behind an exports map that no longer exposes
`src/*`, so with newer dependencies overlaid that import cannot resolve. The
playbook rewrites the import to the v5 `register` API, keeping whatever name the
branch bound it to.

A silent no-op here would leave tag filtering disabled at run time, which looks
like a green run that quietly executed the wrong tests. Every path therefore
either rewrites or asserts.

## Verification before the build

`setup-test-env.yml` checks the checkout before it spends time building:

- The five files the Docker build needs are present: `cypress/package.json`,
  `cypress/yarn.lock`, and the three copied CI files it reads
- `Dockerfile.ci` has no BuildKit-only syntax
- The checkout **declares** every package the run loads at run time
  (`cypress`, `@cypress/grep`, `cypress-mochawesome-reporter`,
  `cypress-multi-reporters`, `mocha-junit-reporter`, `junit-report-merger`,
  `find-test-names`, `globby`), so everything is installed from
  `cypress/yarn.lock` and nothing is added at run time
- The Cypress version comes from what the checkout installs, not from
  `vars.yaml`, when the two disagree

And after the build:

- The image carries the expected Cypress binary
- The image carries kubectl
- The kubeconfig is present and readable
- The imported cluster is reachable *from inside the image*

The last one is informational and cannot fail the build; it is reported so that
a Cypress failure twenty minutes later can be attributed quickly. Reachability
is asserted for real earlier, by `install-k3s-rancher.yml`.

## `.env`

[`templates/env.j2`](../templates/env.j2) renders `.env` next to the playbook,
and `init.sh` passes it to the Cypress container with `--env-file`. It carries
the Rancher URL and credentials, the AWS/Azure/GKE credentials the cloud
provisioning specs need, the imported-node SSH details, Percy and Qase settings,
and the two values that depend on resolution:

```text
CYPRESS_grepTags   the resolved tag expression, including the build-type exclusion
TEST_USERNAME      standard_user when @standardUser is in the tags, else the admin
```

The template renders during `setup`, which is after the build type is known, so
both are already correct there. Two `lineinfile` tasks in the play rewrite the
same keys on the `[provision, setup]` tags, which keeps an `.env` left by an
earlier run from carrying a stale tag expression into this one. A bare
`--tags test` reaches neither; `run-tests.yml` only fixes `TEST_USERNAME`, and
only for `@standardUser`. See [resolver.md](resolver.md#build-type).

`.env` holds credentials. `Cleanup Executor` in the Jenkins child job deletes it
along with `vars.yaml`, and both are in `.gitignore`.

## Other configuration in this directory

| File | Purpose |
| --- | --- |
| `vars.yaml` | The run's configuration. Written by `init.sh` in Jenkins, by hand locally. Git-ignored |
| `vars.yaml.example` | The documented template. AWS, K3s, Rancher, runner versions, dashboard repo, Cypress, reporting |
| `ansible.cfg` | Points `filter_plugins` at this directory, `roles_path` at `../../roles` and `/qa-infra/ansible/roles`, and disables host key checking |
| `inventory` | One line: `localhost ansible_connection=local`. Remote inventories are generated during provisioning |
| `.markdownlint.yaml` | Documentation lint rules |
| `.dockerignore` | Keeps the runner image build context small |
