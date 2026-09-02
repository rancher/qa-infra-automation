# The Jenkins path

Jenkins never runs Ansible directly. It runs one shell script,
[`cypress/jenkins/init.sh`][init] from `rancher/dashboard`, and that script
runs this playbook inside a container. Everything Jenkins-specific lives in the
dashboard repository; everything this playbook knows about Jenkins is three
environment variables and a file called `vars.yaml`.

[init]: https://github.com/rancher/dashboard/blob/master/cypress/jenkins/init.sh

## Two jobs

| Job | Jenkinsfile | Role |
| --- | --- | --- |
| `ui-automation-matrix-multi-job` | `cypress/jenkins/Jenkinsfile_multi` | Parent. Expands a matrix and launches children |
| `ui-automation-matrix-job` | `cypress/jenkins/Jenkinsfile` | Child. One deployment, one Cypress run |

Job definitions live in `rancher/jenkins-job-builder`
(`ui-qa-tests-matrix.yml`). The parent's child job name is parameterised
through `CHILD_JOB`, so a second copy of the matrix can be run beside the real
one without the two colliding.

These replace `ui-automation-ansible-multi-job` and
`ui-automation-ansible-multi-job-prime`, which are the same pipeline duplicated
once per edition. One parent now covers both, because the row's kind selects
the channel instead of the job doing it. The new names run alongside the old
ones so the two can be compared on the same commit; the old pair is deleted
once this has replaced them.

Merge order matters. Both old parents load this same `Jenkinsfile_multi` and
pass the older `TEST_TAGS`, which `TEST_MATRIX` replaces, so they stop with a
message naming the migration as soon as the dashboard change lands. The
dashboard and jenkins-job-builder changes therefore go in together. The
playbook change is backward compatible and can land first on its own.

## The parent: one matrix, many children

`TEST_MATRIX` is a comma-separated list of rows. Each row is one deployment:

```text
kind:tag[:k8s_version]
```

| Field | Meaning |
| --- | --- |
| `kind` | `metadata`, `prime`, `prime-ga`, `community-ga` or `community`. Decides how the child resolves its channel |
| `tag` | A branch head (`head`, `v2.14-head`) for `metadata` and `community`; a Rancher minor (`v2.14`) for `prime`; a minor or a full version (`v2.14.5`) for the two GA kinds |
| `k8s_version` | Optional. Pins K3s for this row only. A `:` in it is rejoined, so a future format carrying one cannot be silently truncated |

Example:

```text
metadata:head, metadata:v2.14-head:v1.35.2+k3s1, prime:v2.14:v1.35.2+k3s1
```

Kinds mix freely, since each row is read on its own:

```text
metadata:v2.15-head, prime:v2.14:v1.35.2+k3s1, prime-ga:v2.13:v1.34.5+k3s1
```

The parent validates each row before it launches anything, and fails the whole
build on a bad one. A `prime` row must name a minor (`^v?\d+\.\d+$`); a
`metadata` or `community` row must name a branch head. That check costs nothing
and happens before any child provisions AWS.

Rows are also deduplicated, on `kind`, the tag with any leading `v` removed, and
the pinned Kubernetes version. `prime-ga:v2.14.5` and `prime-ga:2.14.5` are the
same deployment and run once; the same tag on two Kubernetes versions is two
different tests and runs twice. `CYPRESS_TAGS` is deduplicated the same way. A
repeated row would otherwise pay for a second identical cluster.

`CYPRESS_TAGS` is pipe-separated and crosses with the rows, so three rows and
two tag sets produce six children.

### Why the row carries the kind

This replaced two nearly identical parent jobs, one for Community and one for
Prime, which differed only in a hardcoded `rancher_helm_repo`. The channel is a
property of the row, not of the job, and hardcoding it goes wrong silently: when
a minor moves to Prime-only builds, the Community job keeps passing against an
increasingly stale image. See [resolver.md](resolver.md).

### What the parent writes into the child config

The parent takes `VARS_YAML_CONFIG` as a base and rewrites top-level keys per
child, appending any key the base does not already carry:

| Key | Value | Condition |
| --- | --- | --- |
| `rancher_image_tag` | the row's tag | always |
| `cypress_tags` | the tag set for this child | always |
| `channel_source` | `metadata`, `prime`, `prime-ga`, `community-ga` or `fixed` | always |
| `rancher_helm_repo` | `rancher-com-rc` | only for a `community` row |
| `k3s_kubernetes_version` | the row's k8s | only when the row states one |

The two conditional rows are the interesting ones.

`rancher_helm_repo` is deliberately **not** written for a `metadata` or `prime`
row. Those rows resolve their own channel, and writing the key anyway would
leave a value behind that looked meaningful but was not. Anything reading the
child's config to decide "is this Prime?" therefore gets no answer, which is
correct: at that point in the build there is no answer yet.

`k3s_kubernetes_version` is left alone when the row does not state one, so a
`metadata` row can take it from `branches-metadata.json`. Branches that have not
filled in `e2e.kube.version` (release-2.14 and older, today) keep whatever the
job passed.

Only a `metadata` row reads that key. Every other kind resolves a channel rather
than a branch, so an unpinned row keeps the job's value whether or not the branch
supplies one: `community:v2.15-head` with no third field ran on the base config's
v1.33.10+k3s1 while `metadata:v2.15-head`, the same branch head, ran on the
v1.35.2+k3s1 its branch declares. Both deploy, since the chart accepts either, but
only one of them is the version the branch intends. Pin the field on every row
that is not `metadata`.

### Fan-out

Children run in batches sized from what the agent actually has:

```groovy
ramBound   = (MemAvailable - RAM_RESERVE_MB) / ESTIMATED_RUN_MB
cpuBound   = max(1, nproc - 1)
batchSize  = min(requestedFanout, max(1, min(min(BATCH_SIZE, BATCH_SIZE_CAP),
                                             min(ramBound, cpuBound))))
```

Each batch is a `parallel` block with a 270-minute timeout. All inputs and the
resulting batch size are echoed, so a build that ran fewer children in parallel
than expected says why.

`build(...)` is called with `propagate: false`, so one failing row does not abort
the rest of the batch and the remaining batches still run. The results are
collected and rolled up after the last batch instead, so a green parent does
mean its children passed. See "Child results are collected, not propagated".

## Dropping rows with nothing behind them

A row is dropped in the parent, before any child is launched, so a run that
means nothing costs no child and no AWS.

Only `community:` and `community-ga:` rows are dropped, and only on one signal:
**the newest Prime GA for the minor is ahead of the newest Community GA**. A
recently rebuilt `-head` image is not evidence to the contrary, because the head
image keeps building on both registries after the minor stops. That is exactly
how a Community 2.13 row stayed green for five months while testing an image
frozen since March.

Measured against the live channels:

| Minor | Community GA | Prime GA | Verdict |
| --- | --- | --- | --- |
| 2.13 | `2.13.3` | `2.13.9` | dropped |
| 2.14 | `2.14.3` | `2.14.5` | dropped |
| 2.15 | `2.15.1` | `2.15.1` | kept |
| 2.16 | none | none | kept |

2.16 is the case that makes the rule careful, and it is not a one-off: every
minor passes through it. A minor with no GA on either side is **new**, not
stopped, and its Community head build is the only thing testing it, so dropping
there would remove coverage from the newest minor.

Simulated against a hypothetical 2.17 through its whole lifecycle:

| Phase | Community GA | Prime GA | Verdict |
| --- | --- | --- | --- |
| before launch | none | none | kept |
| Community 2.17.0 ships | `2.17.0` | none | kept |
| first Prime release | `2.17.1` | `2.17.1` | kept |
| both maintained | `2.17.2` | `2.17.2` | kept |
| Prime pulls ahead | `2.17.3` | `2.17.4` | **dropped** |
| long stopped | `2.17.3` | `2.17.9` | **dropped** |

The boundary is a shipped release, not a candidate: Community `2.17.3` against a
Prime `2.17.4-rc1` keeps the row, and it drops only once `2.17.4` is final. So
the row drops itself the month that minor goes Prime-only, and not before.

A channel that cannot be read also keeps the row, since dropping on incomplete
data would remove healthy rows whenever the network hiccups.

`metadata:` rows are never dropped: they follow `branches-metadata.json`, and a
missing branch there is a real misconfiguration rather than a quiet skip. A
`prime:` row that cannot resolve fails in its own child in about two minutes,
before provisioning.

Dropping is visible. The count goes in the build description and each dropped
row is logged with its reason, so a minor going quiet is noticed rather than
silently disappearing. If every row is dropped the build fails, because a green
build that ran nothing is the failure this is meant to remove.

Dropping costs no coverage: a dropped `community:v2.13-head` still leaves
`metadata:v2.13-head` deploying whatever that minor publishes, and `prime:v2.13`
covering its newest release.

## The child: one deployment

Stages in order:

| Stage | What it does |
| --- | --- |
| Pre-Clean | Remove this executor's leftover containers and images |
| Preflight | Require 5 GB free; set the build description from the row |
| Checkout | Clone `rancher/dashboard` at `BRANCH` **and** `qa-infra-automation` at `QA_INFRA_BRANCH`, both shallow |
| Disk | `disk-report.sh before` |
| Run Tests | `cypress/jenkins/init.sh`, 180-minute timeout, exit code captured |
| *(finally)* Grab Results | Confirm `results.xml` and `html/` arrived |
| *(finally)* Description | Rewrite the description from `notification_values.txt` |
| *(finally)* Clean Test Environment | `init.sh destroy`, unless `CLEANUP` is `false`/`no`/`0` |
| *(finally)* Cleanup Executor | Remove containers and images, wipe `vars.yaml` and `.env` from disk |
| *(finally)* Test Report | `junit`, `publishHTML` |
| *(finally)* Slack | `slack-notification.sh` on a non-green result |

The child binds ten credentials (`AWS_*`, `AZURE_*`, `GKE_SERVICE_ACCOUNT`,
`PERCY_TOKEN`, `QASE_AUTOMATION_TOKEN`, `UI_SLACK_*`) and exposes them to
`init.sh` as environment variables. They are never written to the Jenkinsfile,
and `Cleanup Executor` deletes the two files they end up in.

### The build description is written twice

Preflight can only report what the row *asked for*, because the channel and the
build type are not known until the playbook has resolved and deployed. It writes
the requested tag, the row kind (`metadata row`, `prime row`) or, for a fixed
row, the edition implied by the channel.

The `finally` block then rewrites the description from
`notification_values.txt`, which is post-resolution: the image tag actually
deployed, the build type the deployed Rancher reported, and the Cypress
expression actually run.

Before this, the description was derived from `rancher_helm_repo` at Preflight
alone. Since the parent stops writing that key for self-resolving rows, every
such build was labelled `community`, including Prime ones.

### Build status

| Result | Meaning |
| --- | --- |
| SUCCESS | `results.xml` has test cases and no failures |
| UNSTABLE | `results.xml` has failures. The tests failed; the pipeline worked |
| FAILURE | No `results.xml`, or the pipeline threw |

## init.sh, the bridge

```text
JENKINS_WORKSPACE = $WORKSPACE
QA_INFRA_DIR      = $WORKSPACE/qa-infra-automation
PLAYBOOK_DIR      = $QA_INFRA_DIR/ansible/testing/dashboard-e2e
RUNNER_IMAGE      = dashboard-e2e-runner:$EXECUTOR_NUMBER
```

What it does, in order:

1. **Require `qa-infra-automation`** to be in the workspace already. This script
   runs no git at all: the `Checkout` stage puts both repositories there, and a
   missing playbook directory is a hard error naming that stage. The short SHA
   the stage echoes is how you confirm which playbook a build actually ran.
2. **Build the runner image** from `PLAYBOOK_DIR/Dockerfile.quickstart`.
3. **Write `vars.yaml`** into `PLAYBOOK_DIR`, mode 600: `VARS_YAML_CONFIG`
   verbatim, then a credentials block appended from the Jenkins environment
   (`qase_token`, `percy_token`, Azure, GKE), YAML-escaped.
4. **Validate.** `rancher_image_tag`, `cypress_tags` and `job_type` must be
   present. When `job_type: existing`, `rancher_host` is required, must be an
   IPv4 or FQDN **without a port**, and is locked so two builds cannot
   target the same host.
5. **Run the playbook** in the runner container with `--skip-tags test`.
6. **Copy `notification_values.txt`** to the Jenkins workspace, before any
   of the exits below, so a failing build still notifies Slack with details.
7. **Run Cypress** directly, so output streams to the Jenkins console in colour.
8. **Copy results**, meaning `results.xml` and `cypress/reports/html/`, to the
   Jenkins workspace, after `chown`ing the checkout back to the invoking user.

`init.sh destroy` skips step 1 entirely. It runs later in the same build as the
run that created the infrastructure, and the Jenkins `Checkout` stage wipes the
workspace before that run, so the checkout on disk is already this build's own
at the right commit. Fetching again gained nothing and cost a cleanup: a
transient GitHub refusal made `destroy` exit before it reached the playbook,
leaving the run's cloud resources standing. It does step 2, since it needs an
image to run the playbook in, then goes straight to `--tags cleanup,never`.

`vars.yaml` is what tells it there is anything to destroy. That file is written
in step 3, so its absence means the run never reached the point of provisioning.

### Two containers

A build runs two different images, and confusing them is the most common source
of "why is my change not taking effect".

```bash
# 1. The runner. Its entrypoint is the playbook.
docker run --rm -t --init \
  --label "jenkins_build=${BUILD_TAG:-local}" \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "${PLAYBOOK_DIR}:/playbook" \
  -v "${QA_INFRA_DIR}:/qa-infra" \
  -e QA_INFRA_DIR=/qa-infra \
  -e HOST_DASHBOARD_DIR="${PLAYBOOK_DIR}/dashboard" \
  -e AWS_ACCESS_KEY_ID=... -e AWS_SECRET_ACCESS_KEY=... \
  -e PREFIX=... -e EXECUTOR_NUMBER=... -e BUILD_TAG=... \
  "${RUNNER_IMAGE}" --skip-tags test

# 2. The tests. Built by the playbook. Its entrypoint is cypress.sh.
docker run --rm -t --init \
  --name "${container_name}" \
  --label "jenkins_build=${BUILD_TAG:-local}" \
  --shm-size=2g \
  --env-file "${PLAYBOOK_DIR}/.env" \
  -e NODE_PATH="" \
  -v "${PLAYBOOK_DIR}/dashboard:/e2e" -w /e2e \
  "dashboard-test:${EXECUTOR_NUMBER}"
```

Both carry `--label jenkins_build`, which is how `Cleanup Executor` removes this
build's containers without touching a concurrent build's.

The runner has the host's Docker socket, which is how the playbook builds
`dashboard-test` and, in a non-Jenkins run, starts it. `HOST_DASHBOARD_DIR`
tells the playbook the path on the agent, because a bind mount it requests is
resolved by the host daemon and not inside its own filesystem.

### `-e` here is Docker, not Ansible

Every `-e` above sets a container environment variable. None of them is an
Ansible extra-var. The playbook is configured entirely through `vars.yaml`,
loaded by `vars_files`.

This matters more than it looks. Ansible's `-e` extra-vars outrank `set_fact`,
so a value delivered that way cannot be rewritten by the resolver, and a row
would silently deploy the channel it was told to instead of the one it resolved.
`resolve-channel.yml` asserts against exactly this. It also means **a local
reproduction that passes config with `-e` is not reproducing the pipeline**.
Write a vars file and use `vars_files`. See
[resolver.md](resolver.md#precedence).

## What flows back

| Artifact | Written by | Landing place | Consumer |
| --- | --- | --- | --- |
| `results.xml` | Cypress, merged by `jrm` | workspace root | `junit` step, build status |
| `html/` | `cypress-mochawesome-reporter` | `workspace/html` | `publishHTML` |
| `notification_values.txt` | the playbook | workspace root | build description, `slack-notification.sh` |

## HTTP 401 on a public repository

Agents intermittently get `HTTP 401` from github.com cloning a repository that
needs no authentication, in bursts lasting minutes:

```text
stderr: error: RPC failed; HTTP 401 curl 22 The requested URL returned error: 401
fatal: expected flush after ref listing
```

It is not the pipeline's doing. Probing the agent during a burst showed curl
getting 200 for the same ref listing git was refused, no git config in either
scope, and requests for one repository alternating between refused and served.
That is throttling, which GitHub signals as 401 rather than 429 for an
unauthenticated git operation. Credentials, credential helpers,
`http.extraHeader`, `.netrc`, a proxy and repository visibility were all ruled
out by testing.

`checkoutWithRetry` in `Jenkinsfile` gives both clones one policy: two attempts
with a 20 second pause, then the source tarball. The retry is short on purpose,
since bursts ran to eight minutes and the tarball succeeds immediately. It is
kept only because a git checkout records a revision on the build and a tarball
cannot.

```text
https://codeload.github.com/<owner>/<repo>/tar.gz/<commit>
```

A different host, and a plain HTTPS download rather than the git smart
protocol, so it is served while the git endpoint is refusing. Nothing
downstream needs a repository, only the tree. The branch is resolved to a
commit first through `api.github.com` so the build records what it took, and
the archive is refused if its top directory is not that commit.

The durable fix is authenticating the clone, which raises the limit and counts
it per account. `Jenkinsfile` already passes `userRemoteConfigs:
scm.userRemoteConfigs`, so it needs no change: set `credentials-id` on the job
definition. It has to be a **Username with password** holding a PAT, because
`GitSCM` cannot bind a Secret text credential over HTTPS. **A `credentialsId`
is safe to commit**: it names a credential, it is not the secret.

## Five traps Groovy parsing does not catch

A Jenkins pipeline is not plain Groovy. It is rewritten into a resumable CPS
form and run inside a script-security sandbox, and neither shows up when the
file parses locally. All five of these were found by running the job, not by
reading it.

| Trap | Symptom |
| --- | --- |
| `java.util.regex.Matcher` is not serialisable | `NotSerializableException` when a match result is held across a step. Consume it immediately, or in an `@NonCPS` method |
| `def x` at script scope is not a binding property | The variable is invisible inside some closures |
| A CPS local does not always survive an `sh()` step | Value silently lost after the step returns |
| Assignment without `def` | Jenkins logs a memory-leak warning |
| The sandbox rejects most `new java.*` constructors | `RejectedAccessException: Scripts not permitted to use new java.util.concurrent.ConcurrentHashMap`, thrown at run time |

The last one is worth stating plainly: a plain `[:]` is the right choice anyway.
CPS runs `parallel` branches on a single thread, so branches writing distinct
keys need no concurrent collection.

The shape that works here: everything inside the one `node{}`, `def`-declared,
after the machine-fact `sh()` calls and immediately before the batching.

## Child results are collected, not propagated

Children are launched with `propagate: false` so one failing row does not abort
the rest of the batch. On its own that also lets the parent finish **green while
every child failed**, which is how a scheduled matrix reports success having
proved nothing. Observed: one parent finished `SUCCESS` with all twelve children
`FAILURE`.

Each branch records its own result, and after the last batch the parent takes
the worst one, printing a line per child. A child that never reported at all is
counted as a failure, since a row nobody ran is not a row that passed.

## Local reproduction

The full chain can be exercised without AWS by pointing a run at an existing
Rancher:

```bash
export VARS_YAML_CONFIG='job_type: existing
rancher_host: rancher.example.com
rancher_image_tag: v2.14-head
channel_source: metadata
cypress_tags: "@generic"
...'
cypress/jenkins/init.sh
```

`job_type: existing` skips provisioning, and with it the AWS variable
validation in `pre_tasks`, so no cloud credentials are needed. `rancher_host` is
required, is locked for the duration, and must not carry a port.

What cannot be reproduced locally on an unprivileged host is the Rancher deploy
itself: K3s needs kernel settings that rootless containers cannot set. Resolver
and tag-adjustment behaviour can be exercised offline against the real task
files; a Cypress run against a real Rancher needs the Jenkins path.
