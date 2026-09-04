# Playbook architecture

`dashboard-e2e-playbook.yml` is a single play against `localhost`. Everything it
does to a remote machine, it does by shelling out to OpenTofu, to another
playbook in this repository, or to a container. Reading it top to bottom is the
fastest way to understand a run, and this page is a map for that read.

## Phases are tags, not plays

There are four phases, selected with `--tags` / `--skip-tags`:

| Tag | What it does |
| --- | --- |
| `provision` | EC2 instances, DNS, SSH keys, K3s, Rancher |
| `setup` | Clone dashboard, overlay CI files, build the `dashboard-test` image, write `.env` |
| `test` | Run Cypress in that image, collect JUnit XML and the HTML report |
| `cleanup` | `tofu destroy` every workspace, remove artifacts. Also tagged `never`, so a run that names no tags never reaches it |

Because a phase is a tag rather than a play, tasks that several phases need are
tagged with all of them. Resolution is tagged `[provision, setup]` so that a
`--tags setup,test` re-run against already-provisioned infrastructure still
knows which chart and image it is talking about.

`cleanup` carries `never` on purpose. A task tagged `never` is skipped when no
tags are given and when `--tags all` is given, so a full run cannot destroy
anything by accident. Naming the tag runs it: both `--tags cleanup` and
`--tags cleanup,never` work, and `init.sh destroy` uses the latter.

### The phase flag

`pre_tasks` ends by setting one fact:

```yaml
_is_setup_or_test: "{{ 'setup' in ansible_run_tags
                    or 'test' in ansible_run_tags
                    or 'all' in ansible_run_tags }}"
```

Tasks that only make sense when there will be a test run are gated on it: the
build-type question, the Cypress tag adjustment, the `.env` edits and
`notification_values.txt`. A provision-only run and a cleanup run skip all of
them.

## Order of operations

```text
pre_tasks  [always]
  Create outputs directory
  Validate required AWS variables          when recurring
  Recover rancher_host from tofu state     when not already known, not cleanup
  Recover ssh_key path from outputs        when recurring, unset, not cleanup
  Validate rancher_host for existing job   when existing, not cleanup
  Validate rancher_host is available       when setup/test without provision
  Display pipeline info
  Set phase flags                          → _is_setup_or_test

tasks
  1  Resolve the channel for this row      [provision, setup]
  2  Resolve Rancher helm version          [provision, setup]
  3  Provision infrastructure               [provision]
  4  Install K3s and deploy Rancher         [provision]
  5  Ask the deployed Rancher which build   [provision, setup]
  6  Set adjusted Cypress tags              [provision, setup]
  7  Show adjusted Cypress tags             [provision, setup]
  8  Update Cypress tags in .env            [provision, setup]
  9  Update TEST_USERNAME for @standardUser [provision, setup]
 10  Setup test environment, build image    [setup]
 11  Run Cypress tests                      [test]
 12  Write notification values              [always]
 13  Cleanup infrastructure                 [cleanup, never]

post_tasks [always]
  Final status
  Fail if tests failed
```

Two orderings in that list are deliberate and both were bugs before they were
decisions.

**Resolution comes first, before provisioning.** Steps 1 and 2 read published
chart indexes over HTTP and need nothing that provisioning produces. Putting
them first means a row that cannot resolve, such as a Prime row for a minor
with no release yet, fails in seconds and leaves no AWS resources behind. It
used to fail several minutes in, after an EC2 fleet had already come up.

**The build-type question comes after the deploy, not before.** Step 5 asks the
running Rancher what it is. It cannot run in `pre_tasks`, because there is no
Rancher to ask yet. The tag adjustment in step 6 therefore has to sit in `tasks`
after step 4, not in `pre_tasks` where it used to be. See
[resolver.md](resolver.md#build-type) for why the channel is not an acceptable
substitute.

## Variables that carry state

Almost all cross-stage state travels in facts set by the resolver and read
later. The ones that matter:

| Variable | Set by | Read by |
| --- | --- | --- |
| `channel_source` | `vars.yaml` (Jenkins writes it per row) | `resolve-channel.yml` |
| `rancher_helm_repo` | `vars.yaml`, or rewritten by `resolve-channel.yml` | `resolve-helm-version.yml`, the Rancher deploy |
| `rancher_chart_url` | `resolve-channel.yml` (metadata mode) or the repo map | `resolve-helm-version.yml` |
| `rancher_chart_tag` | `resolve-channel.yml` (metadata mode only) | `resolve-helm-version.yml` |
| `rancher_channel_shapes` | either of the above | `rancher_chart_select` |
| `rancher_version` | `resolve-helm-version.yml` | the Rancher deploy, `notification_values.txt` |
| `rancher_image` | either resolver | the Rancher deploy |
| `rancher_image_tag_resolved` | either resolver | the Rancher deploy, `notification_values.txt` |
| `k3s_kubernetes_version` | `vars.yaml`, overridden only by metadata mode when the branch fills it in | `install-k3s-rancher.yml` |
| `rancher_build_type` | the tag adjustment, step 6 | `notification_values.txt`, Slack, the Jenkins build description |
| `cypress_tags` | `vars.yaml`, rewritten by step 6 | `.env`, `grep-filter.ts`, Cypress |
| `cypress_exit_code` | `run-tests.yml` | `post_tasks` |

`resolve-channel.yml` defaults `channel_source`, then clears
`rancher_chart_url`, `rancher_chart_tag` and `rancher_channel_shapes` before it
resolves anything. `resolve-helm-version.yml` treats a set `rancher_chart_url`
as "the channel is already decided, skip the repo map", so a stale value from a
previous include would silently change the answer. Clearing first makes the
result a function of `channel_source` alone.

## Paths

The play derives its own paths, and they differ between a Jenkins run and a
local one because `WORKSPACE` is not exported into the runner container.

| Variable | Jenkins | Local `run.sh` |
| --- | --- | --- |
| `workspace_dir` | `/playbook` (env `WORKSPACE` unset in the container) | `/playbook` |
| `dashboard_dir` | `/playbook/dashboard` | `/playbook/dashboard`, or `dashboard_src` |
| `host_dashboard_dir` | env `HOST_DASHBOARD_DIR`, the path on the agent | same |
| `qa_infra_dir` | `/qa-infra` | `/qa-infra` |
| `outputs_dir` | `/playbook/outputs` | same |
| `executor_tag` | env `EXECUTOR_NUMBER` | `0` |

`host_dashboard_dir` exists because the playbook talks to the *host's* Docker
daemon through a mounted socket. When it asks that daemon to bind-mount the
dashboard checkout into the Cypress container, the path has to be the one the
daemon can see, not the one inside the runner container. Getting this wrong
produces an empty `/e2e`.

`executor_tag` scopes the built image to `dashboard-test:{{ executor_tag }}`, so
two Jenkins builds on the same agent do not overwrite each other's image.

## Provisioning

`tasks/provision.yml` runs OpenTofu against
`tofu/aws/modules/cluster_nodes` in this repository, in up to three workspaces
in parallel via `async`:

| Workspace | Purpose |
| --- | --- |
| `rancher-server` | The nodes Rancher itself runs on |
| `importcluster` | A second cluster the tests import |
| `customnode` | A bare node for custom-cluster registration tests |

`.tfvars` for each comes from [`templates/tfvars.j2`](../templates/tfvars.j2).
After apply, `scripts/generate_inventory.py` turns the `cluster_nodes_json`
output of `rancher-server` and `importcluster` into static Ansible inventories
under `outputs/inventory-*`, with `kube_api_host` and `fqdn` baked into
`all.vars`. `customnode` gets no inventory: it is a bare machine the tests
register themselves, so only its IP is read back.

`tasks/install-k3s-rancher.yml` then calls two playbooks from elsewhere in this
repository against those inventories:

- `ansible/k3s/default/k3s-playbook.yml`
- `ansible/rancher/default-ha/rancher-playbook.yml`

Those are shared with other pipelines. A change to them affects more than
dashboard-e2e.

`tasks/cleanup.yml` destroys the workspaces in a loop, removes the built image
and deletes `.env` and the dashboard checkout. It tolerates missing workspaces,
because a run that failed during provisioning has fewer of them than a run that
succeeded.

## Result handling

`run-tests.yml` runs the container with `failed_when: false`. A failing test
suite is a result, not a broken pipeline step, so the exit code is recorded in
`cypress_exit_code` and the decision is made in `post_tasks`. This is what lets
Jenkins distinguish "the tests failed" (yellow) from "the pipeline broke" (red);
see [jenkins.md](jenkins.md#build-status).

`notification_values.txt` is written next to the playbook and is the only
structured output the run publishes about itself:

```text
RANCHER_VERSION            the chart version deployed
RANCHER_IMAGE_TAG          the image tag deployed, after resolution
RANCHER_CHART_URL          which channel it came from
RANCHER_HELM_REPO          the channel name, after resolution
RANCHER_BUILD_TYPE         prime | community, as reported by the deployed server
RANCHER_BUILD_TYPE_SOURCE  whether that was observed or assumed
CYPRESS_TAGS               the tag expression actually run
KUBERNETES_VERSION         the K3s version deployed
DASHBOARD_BRANCH           the branch the tests came from
```

Everything in that file is post-resolution. That is the point of it: the request
is in the job parameters, and this is what the request turned into.

## The runner image

[`Dockerfile.quickstart`](../Dockerfile.quickstart) builds
`dashboard-e2e-runner`, a `python:3.12-alpine` image with OpenTofu, Helm,
kubectl, the Docker CLI and Ansible. Its entrypoint is the playbook itself, so
running the image *is* running the play.

### Helm is held on the 3 series

Not conservatism: helm 4 changed `--dry-run` to never consult the cluster, so
it renders against the Kubernetes version helm itself was built against,
currently `v1.36.0`. The compatibility pre-flight in
`ansible/rancher/default-ha/rancher-playbook.yml`, which this suite calls to
deploy, uses that flag and so reports chart `2.13.9`, pinned `< 1.35.0-0`, as
`INCOMPATIBLE KUBERNETES VERSION` on a cluster it fully supports. A Renovate
bump to `v4.2.4` on 2026-09-01 is what introduced it.

The playbook invokes `helm` by name, so the binary comes from this image's
`PATH`. Pinning it here fixes the deploy without editing a module this suite
only borrows. Measured on 3.21.4: charts 2.13.9, 2.14.5 and 2.15.1 all pass,
and rendering 2.13.9 against a 1.35 cluster is still refused, so the check
still does its job.

helm 3 is current rather than legacy: 3.21.4 shipped the day after 4.2.4, and
3.22 is in release candidate. Renovate will keep proposing v4; taking it needs
that pre-flight to name the Kubernetes version explicitly first.

`ansible-core` is pinned `<2.17`, which today resolves to **2.16.19**. That pin
is not incidental. The collections it installs, `community.docker <5` and
`community.crypto <3`, are the last versions that support it, and two bugs in
this pipeline's history only reproduced on 2.16. If you are validating a change
to Jinja, to `set_fact` precedence, or to anything that touches native types,
validate it in this image rather than in a local virtualenv:

```bash
docker build -t dashboard-e2e-runner -f Dockerfile.quickstart .
docker run --rm --entrypoint sh dashboard-e2e-runner -c 'ansible --version'
```

### Why the base image is stuck on Python 3.12

Three things are welded together, and a dependency bot will periodically propose
moving one of them on its own:

```text
python:3.12-alpine   ->  ansible-core <2.17 (2.16.19)  ->  community.docker <5
                                                           community.crypto <3
```

ansible-core 2.16's supported control-node Pythons stop at 3.12, and the two
collection pins exist only because 5.x and 3.x require 2.17 or newer. So a bump
of the base image alone cannot be merged: the cap has to move in the same
change, and the collections have to be revalidated under it.

The rest of this repository is already on `ansible-core==2.21.3`
(`requirements.txt`), so closing this gap is worth doing. Some of the
groundwork is measured. Across `python` 3.12 and 3.14, and `ansible-core`
2.16.19 and 2.21.3, all four combinations gave identical, correct results for:
`--syntax-check`; the resolver run against the live chart indexes, which agreed
on `2.15.1-rc2` from `rancher-latest` every time; the build-type expression
including the native-types trap; the `rancher_charts` filter plugin; and
importing `community.crypto`, `community.docker` and `kubernetes.core` with the
pins in place.

That is encouraging but not sufficient, and it is not a reason to move today.
Nothing in it exercises a real provision, a real Rancher deploy or a real
Cypress run, which is where a collection change would actually show. It also
does not make 3.14 a *supported* control node for 2.16; it only shows nothing
observable breaks. A cap raise wants a full staging run behind it.

## Local runs

[`run.sh`](../run.sh) is the same image with argument handling: it detects
Docker or Podman, mounts the playbook and `qa-infra` directories, passes
credentials through a temporary file rather than the command line, and maps
phases onto tags.

```bash
./run.sh                     # no --tags: provision, setup and test, never cleanup
./run.sh stream              # setup + test, live Cypress output
./run.sh test                # re-run tests against provisioned infrastructure
./run.sh destroy             # --tags cleanup,never
```

Note the first one. A bare `./run.sh` passes no `--tags`, which Ansible treats
as everything except `never`, so it provisions, sets up and tests but leaves the
infrastructure standing. Tearing it down is a separate `./run.sh destroy`.

`stream` mode exists because the `test` tag runs Cypress through Ansible, which
buffers. Streaming skips that tag and runs the container directly, which is also
exactly what `init.sh` does in Jenkins. See
[jenkins.md](jenkins.md#two-containers).
