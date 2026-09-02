# The resolver

A test run has to answer three questions before it can do anything useful:

1. **Which channel** does this row deploy from?
2. **Which chart version and image tag** on that channel?
3. **Which build type** did it get, Prime or Community?

The resolver answers the first two before any infrastructure exists, and the
third only after Rancher is running, because only the running server knows.

This is [rancher/qa-tasks#2410][2410]. The motivation is that hardcoding any of
the three fails *silently*: the run stays green while testing the wrong build.

[2410]: https://github.com/rancher/qa-tasks/issues/2410

## Words used throughout

| Term | Means |
| --- | --- |
| **minor version** | A Rancher `X.Y`, such as 2.15. Every `2.15.*` belongs to it: `2.15.0-alpha3`, `2.15.1-rc2`, `2.15.1`, `2.15.2-<sha>-head`. Going 2.15 to 2.16 is a new minor |
| **line**, release line | The same thing. The code and its error messages use this word, so it is kept here where it describes the code: `_line_of`, `rancher_chart_line_versions`, and *"That line is published there but carries no release chart yet"* |
| **chart line** | Which minor's *charts* to select from, as distinct from which minor the server image is on. The two can differ |
| **channel** | One published Helm repository, such as `rancher-latest`. A channel carries charts for many minors |
| **shape** | The pre-release suffix of a version: `-rc`, `-alpha`, `-head`, or none for a final release |
| **release ladder** | The ordering of shapes within one minor: a final release outranks its own release candidate, which outranks an alpha |
| **head** | A build of a branch as it currently stands, published per commit as `X.Y.Z-<sha>-head`. Not a release: it names a different build every time |
| **build type** | Prime or Community. A property of the build itself, not of where it was published |

The chart line matters because a branch's chart and its server image are not
always on the same minor. The dashboard's `master` branch builds the next minor
while the chart channel is named for a released one, so picking the wrong one
deploys a chart that does not match the image.

## Where the code is

| Step | File |
| --- | --- |
| Which channel | [`tasks/resolve-channel.yml`](../tasks/resolve-channel.yml) |
| Which chart and image | [`tasks/resolve-helm-version.yml`](../tasks/resolve-helm-version.yml) |
| Ordering the release ladder | [`filter_plugins/rancher_charts.py`](../filter_plugins/rancher_charts.py) |
| Which build type | `Ask the deployed Rancher which build it is`, in the playbook |

`resolve-channel.yml` is the only file that differs by mode. It rewrites the two
inputs `resolve-helm-version.yml` reads, `rancher_helm_repo` and
`rancher_image_tag`, and hands the rest over through `rancher_chart_url`,
`rancher_chart_tag` and `rancher_channel_shapes`. A metadata row also settles
`rancher_image`, `rancher_image_tag_resolved` and, when its branch states one,
`k3s_kubernetes_version`. Everything below it is the same code in every mode,
which is what keeps a new mode from being a second implementation.

## Step 1: which channel

Driven by `channel_source`, which the Jenkins parent writes per row.

`channel_source` says **how the channel is found**, not which channel it is:

| Row kind | `channel_source` | Meaning |
| --- | --- | --- |
| `metadata:` | `metadata` | ask `branches-metadata.json` which registry the branch uses |
| `prime:` | `prime` | search the Prime channels for the newest release |
| `community:` | `fixed` | resolve nothing, use `rancher_helm_repo` as written |

A `community:` row has nothing to resolve, since it means Docker Hub always, so
the parent writes both keys: `channel_source: fixed` and
`rancher_helm_repo: rancher-com-rc`. That is why a child logs
`CHANNEL_SOURCE=fixed` for a Community row, and why the edition is in the repo
rather than in the source.

### `fixed`, the default

Take `rancher_helm_repo` as given. Nothing is rewritten, so a job that has not
opted in behaves exactly as it did before any of this existed. The repo name is
mapped to a URL, an image and a set of pre-release shapes in
`resolve-helm-version.yml`:

| `rancher_helm_repo` | Chart URL | Image registry | Shapes |
| --- | --- | --- | --- |
| `rancher-prime` | `charts.rancher.com/server-charts/prime` | `registry.suse.com` | any. Prefer `rancher-prime-ga`: identical digests, but images-locations.md names only `registry.rancher.com` |
| `rancher-prime-ga` | `charts.rancher.com/server-charts/prime` | `registry.rancher.com` | any |
| `rancher-latest` | `charts.optimus.rancher.io/server-charts/latest` | `stgregistry.suse.com` | `-rc`, `-alpha` |
| `rancher-alpha` | `charts.optimus.rancher.io/server-charts/alpha` | `stgregistry.suse.com` | `-alpha` |
| `rancher-community` | `releases.rancher.com/server-charts/stable` | Docker Hub | any |
| `rancher-com-rc` | `releases.rancher.com/server-charts/latest` | Docker Hub | any |
| `rancher-com-alpha` | `releases.rancher.com/server-charts/alpha` | Docker Hub | any |

"Shapes" is the set of pre-release suffixes the channel selects when a *line* is
requested. Empty means any release counts, which is right for a GA channel.

### `metadata`, follow the branch

Reads the dashboard team's
[`branches-metadata.json`][meta], which is where they record what each branch
builds.

[meta]: https://github.com/rancher/dashboard/blob/master/branches-metadata.json

```text
rancher_image_tag: head        →  branch master
rancher_image_tag: v2.14-head  →  branch release-2.14
```

From the branch entry it takes:

| Metadata key | Becomes |
| --- | --- |
| `e2e.rancher-image.{registry,namespace,name}` | `rancher_image` |
| `e2e.rancher-image.tag` | `rancher_image_tag_resolved` |
| `milestone.version` | which minor's charts to use |
| `e2e.kube.version` | `k3s_kubernetes_version`, when non-empty. Read in this mode only; other modes keep the job's value |

The chart then comes from that minor's own head channel:

```text
rancher_chart_url:  charts.optimus.rancher.io/server-charts/release-<line>
rancher_helm_repo:  metadata-release-<line>
rancher_chart_tag:  head
```

Three details in there are non-obvious.

**The chart line comes from `milestone.version`, not from the `helm.repo-url`
key.** That key is a workaround for a naming mismatch, not a statement of
intent: chart channels are always `release-X.Y`, but the dashboard's top branch
is called `master` and there is no `server-charts/master` to name, so master's
key points at the previous minor. The milestone is the minor the branch actually
builds, and it agrees with the `CATTLE_CHART_DEFAULT_BRANCH` baked into the
images.

**The chart request is not the image tag.** A branch head channel carries only
that branch's head charts, one per commit, so the chart wanted is simply the
newest of them, hence `rancher_chart_tag: head`. The image keeps the branch
head tag the metadata names. The two do not share a version, and the pairing is
stated rather than derived.

**The registry is read from the file, not probed.** Which registry a minor
publishes to is a human decision the dashboard team records, and release-2.14
has moved between registries more than once. No freshness signal can express
that.

A branch that is missing from the file is a hard failure listing the valid
branches, not a row that quietly skips. Silent skipping is the failure mode this
whole approach exists to remove.

### `prime`, the newest release of a minor

```text
rancher_image_tag: v2.14  →  the newest 2.14 Prime release, wherever it lives
```

The row must name a minor (`^v?[0-9]+[.][0-9]+$`). `head` names no minor, and
a full version names one build.

All three Prime channels are fetched and the highest pick wins. A channel that
answers 404 is skipped rather than failing the row, because the release team is
consolidating the Prime pre-release charts into `rancher-latest` and will retire
the alpha repo once that is done. A channel that is unreachable still fails: it
might hold the newest release, and resolving from the rest would quietly deploy
an older build.

All three Prime channels are fetched and the highest pick wins:

```text
rancher-prime-ga  charts.rancher.com/server-charts/prime
rancher-latest    charts.optimus.rancher.io/server-charts/latest
rancher-alpha     charts.optimus.rancher.io/server-charts/alpha
```

Which one holds the newest release changes as a minor progresses: the GA in
`rancher-prime-ga` once it ships, an rc in `rancher-latest` before that, or an
alpha in `rancher-alpha` for a minor that has not reached rc. Naming one by hand
is wrong in every direction and the wrongness moves, so all three are asked.

**The GA channel is not optional.** `charts.optimus.rancher.io` stopped
receiving final releases at 2.14.3, so every newer GA lands only in
`charts.rancher.com/server-charts/prime`. Asking the pre-release channels alone
resolved "the newest release" to the last release candidate of a version that
had already shipped, for every minor:

| Minor | Pre-release channels alone | With the GA channel |
| --- | --- | --- |
| 2.13 | `2.13.9-rc2` | `2.13.9` |
| 2.14 | `2.14.5-rc2` | `2.14.5` |
| 2.15 | `2.15.1-rc2` | `2.15.1` |

`rancher-prime-ga` rather than `rancher-prime`: they serve the same charts, but
the former resolves images to `registry.rancher.com`, which answers an anonymous
pull, while the latter uses `registry.suse.com` and is gated.

The ordering already ranked a final release above its own rc, so nothing in
`filter_plugins/rancher_charts.py` changed. The channel was simply not being
asked.

### A minor with no Prime release yet

A minor ships Community first, so it has Prime builds for months before its
first Prime release. 2.16 has dozens of Prime head charts and no release today, and
does not get one until 2.16.1.

A Prime row therefore takes **the newest release if the minor has one, and the
newest head build if it does not**:

| Minor | Resolves to | Kind |
| --- | --- | --- |
| 2.13, 2.14, 2.15 | `2.13.9`, `2.14.5`, `2.15.1` | release |
| 2.16 | `2.16.0-<sha>-head` from `rancher-latest` | head build |
| a minor on no Prime channel | fails | none |

Releases always win where one exists, so a minor reverts to releases by itself
the day it ships, with no configuration change.

A head pick also names its own dashboard branch. The tag it resolves to is a
chart version, and `setup-test-env.yml` normally reads the branch off that: for
a release that is right, since `2.15.1` belongs to `release-2.15`. For a head
build of a minor with no release it is wrong, because that minor is still built
on `master` and has no release branch cut: `2.16.0-<sha>-head` would send the
run to a `release-2.16` that does not exist. The resolver therefore asks
`branches-metadata.json` which branch carries that milestone and publishes
`dashboard_branch_resolved`.

That survives a branch cut without changes. Simulated against a future
`branches-metadata.json` where `master` has moved to 2.17:

| Row | Chart | Channel | Dashboard branch |
| --- | --- | --- | --- |
| `prime:v2.17` | `2.17.0-<sha>-head` | `rancher-latest` | `master` |
| `prime:v2.16` | `2.16.4` | `rancher-prime-ga` | `release-2.16` |
| `prime:v2.15` | `2.15.8` | `rancher-prime-ga` | `release-2.15` |

The roles shift by one minor and nothing needs editing: 2.16 stops falling back
the moment it has a release, and 2.17 starts. The report says which of the two
it got, in those words, because a head build is not reproducible: the same row
resolves to a different commit tomorrow, so a result worth keeping has to record
the version rather than the row.

Head charts are ordered by publication date, not by version. A commit sha
carries no order, so sorting one picks whichever commit has the highest hex
rather than the most recent build.

### Both build types of one minor

Both are reachable for 2.16 today, by different routes:

| Want | Row | Resolves to | Reports |
| --- | --- | --- | --- |
| Community 2.16 | `metadata:head` | `rancher/rancher:v2.16-<sha>-head` from Docker Hub, chart from `server-charts/release-2.16` | `community` |
| Prime 2.16 | `prime:v2.16` | `stgregistry.suse.com/rancher/rancher:v2.16.0-<sha>-head` | `prime` |

The two head builds are different builds, not the same build served twice. They
differ in tag scheme, and that is what tracks the type: `v2.16-<sha>-head` is
the branch head, `v2.16.0-<sha>-head` is one commit of the next patch.

The resolved chart is then named in full, so the channel's own shape filter
cannot exclude it and a re-run resolves the same chart rather than drifting.

### `prime-ga` and `community-ga`, a shipped release

`prime:` walks the release ladder, so with 2.15.1 shipped it returns
2.15.2-alpha1 the day that patch opens, and a head build for a minor with no
release at all. That is right for the weekly rc and alpha pass and wrong for
verifying a release that has just gone out.

A GA row reads one edition's release channel and only final `X.Y.Z`, so the
answer always shipped. It also accepts a full version, which `prime:` does not,
so a run can pin the release it means to test.

| Kind | Channel read | Example |
| --- | --- | --- |
| `prime-ga:` | `rancher-prime-ga` | `prime-ga:v2.15` -> 2.15.1 |
| `community-ga:` | `rancher-com-rc` | `community-ga:v2.15` -> 2.15.1 |

The edition is part of the kind because the same version number is a different
build on each side: chart 2.15.1 deploys
`registry.rancher.com/rancher/rancher:v2.15.1` for Prime and
`rancher/rancher:v2.15.1` for Community, and those images have different
digests. Neither kind sets the image tag; see "Never set the image tag for a
released chart" below.

`community-ga:` is dropped by the parent on the same signal as `community:`,
since a minor whose Community releases have stopped serves a frozen chart.

## Step 2: which chart version

`resolve-helm-version.yml` fetches the channel's `index.yaml` over HTTP and
hands `entries.rancher` to `rancher_chart_select`.

It reads the index rather than calling `helm search` for three reasons: `helm
search` requires `helm repo add` first, it truncates its table output and
mangles commit-named versions into strings no registry can serve, and the index
carries a `created` date per chart, which is the only thing that can order head
builds.

The selection logic is Python rather than Jinja because ordering a release
ladder is real logic, and keeping it in one module makes the rules reviewable.

### Ordering

Two properties of the published charts drive the implementation:

**A version is not a string.** `2.13.10` is newer than `2.13.9`, `rc10` is newer
than `rc2`, and a final release is newer than its own release candidate. Lexical
sorting gets all three wrong. `_sort_key` returns
`(major, minor, patch, stage, number)` with `GA=3 > rc=2 > alpha=1 > other=0`.

**A commit-named chart has no order at all.** Head builds are published as
`X.Y.Z-<sha>-head`, and a sha is not a sequence: sorting picks whichever commit
has the highest hex digits. Only the index `created` date says which is newest,
and `rancher_chart_newest_head` uses it.

### What a request resolves to

| Request | Resolves to |
| --- | --- |
| `head` | The newest minor, then that minor's newest head build by date. A channel that publishes no head charts falls back to that minor's newest release |
| `v2.15-head` | The newest **release** on the 2.15 line. A branch head image ships no chart of its own |
| `v2.15` | Same: the newest release on that minor, filtered by the channel's shapes |
| `2.14.3` | Narrowed further, so it cannot answer with 2.14.6 |
| `2.16.0-69212c2-head` | Taken exactly as written, shapes bypassed |

An exact match is always honoured first, so an explicit pin is never silently
upgraded, and the leading `v` is optional throughout.

Verified against the live indexes. On the community channel, which carries
releases only, `head`, `v2.15-head` and `v2.15` all resolve to `2.15.1`, while
`2.14.3` stays on `2.14.3` rather than climbing to that minor's newest. On a
`release-2.16` head channel, `head` resolves to a commit-named chart chosen by
its `created` date.

When nothing matches, the failure lists what the minor *does* carry:

```text
No chart in rancher-latest matches 'v2.16'. That line is published there but
carries no -rc or -alpha chart yet; its newest are: 2.16.0-69212c2-head ...
Pin one of those as rancher_image_tag to run it on purpose, or use a channel
that carries a release for this line.
```

The bare "nothing matched" points away from the answer when the version is
sitting in the listing in a shape the channel does not select.

### And the image tag

```yaml
rancher_image_tag_resolved: "{{ ('v' ~ rancher_version)
                                if rancher_image | length > 0
                                else rancher_image_tag }}"
```

A channel that pins an image uses the chart version, because there the chart and
the image are built together. A community channel passes the requested tag
through, because there the tag is what selects the build. A `metadata` row has
already decided and is skipped entirely: it keeps the branch head tag its file
names, which is not a chart version and must not be replaced by one.

### Never set the image tag for a released chart

A `prime-ga:` or `community-ga:` row sets `rancher_image_tag_from_chart`, and
overrides neither the image nor its tag. A released chart already carries both:
the registry in `systemDefaultRegistry`, and the tag through the chart helper
`default .Chart.AppVersion (default .Values.image.tag (default ""
.Values.rancherImageTag))`, so an empty `rancherImageTag` lets the chart answer.

Supplying one can only repeat the chart or contradict it, and contradicting it
is not theoretical. Charts are numbered `2.15.1` while the image is tagged
`v2.15.1`, so passing the chart version asks for `rancher/rancher:2.15.1`, a
404. `helm template` shows both outcomes:

| `rancherImageTag` | image deployed |
| --- | --- |
| unset | `rancher/rancher:v2.15.1`, from `appVersion` |
| `2.15.1` | `rancher/rancher:2.15.1`, a 404 |

`appVersion == "v" + version` holds on every chart in every channel, checked
across all 2,623 entries published today, so
the chart's own answer is always the right one. `rancher_chart_tag` still names
the chart exactly, since that selects which chart installs, and
`rancher_image_tag` keeps the `v` spelling for the rest of the run, which reads
it to pick the dashboard branch and to report what ran, not to deploy it.

## A stopped minor, locally

Jenkins drops a `community:` row whose minor has stopped publishing, because a
scheduled matrix has nobody watching it. A local run is deliberate, so the
playbook does not override what was asked for: it warns and continues.

```text
WARNING: the 2.13 minor stopped at Community 2.13.3 while Prime is at 2.13.9,
so its Community head image may not have been rebuilt in months.
```

`docker.io/rancher/rancher:v2.13-head` was last pushed in March 2026 and is
still served, so a run against it looks healthy and tests an image half a year
old. The warning fires on the same signal Jenkins drops on, and the build type
assertion below is what actually stops a wrong result.

## Verifying the row got what it asked for

Resolving correctly and deploying correctly are different things, and a row that
resolved wrongly but deployed anyway produces months of green runs against the
wrong software. So after deployment the run asserts the build type it actually
got, using the answer it already has from `/rancherversion`:

| Kind | Asserted |
| --- | --- |
| `prime:` | the deployed build reports `prime` |
| `community:` | the deployed build reports `community` |
| `metadata:` | **nothing** |

A `metadata:` row is excluded deliberately. It names a branch, and its edition
follows whichever registry that branch currently publishes to, so it has no
expectation to violate. Asserting either value would fail a correct run on one
side of 11 September 2026, when the floating `vX.Y-head` tags move onto Prime
builds.

The check reads the resolved **channel**, not `channel_source`: the parent maps
a `community:` row to `channel_source: fixed` with
`rancher_helm_repo: rancher-com-rc`, and `fixed` can name either edition, so the
source alone does not say what was asked for. It is skipped when there was no
Rancher to ask, since the fallback infers the type from the channel and
asserting it would only restate the guess.

## Step 3: which build type {#build-type}

Cypress has tags for tests that only apply to one build type: `@prime`, and
`@noPrime` for tests that do not apply to Prime. A run must exclude whichever it
is not, or it fails tests that were never going to pass.

**The build type is a property of the build, and only the build can report it.**

This was got wrong twice before it was got right, and both wrong answers looked
reasonable:

| Signal | Why it fails |
| --- | --- |
| The **channel** | A `metadata` row resolves its chart from a per-minor head repo whose name says nothing about the edition |
| The **image registry** | `stgregistry.suse.com` serves `v2.14-head`, which reports Community, *and* `v2.14.5-rc2`, which reports Prime. Same registry, both types |

Verified directly, by reading `RANCHER_VERSION_TYPE` out of the image configs:

| Image | `RANCHER_VERSION_TYPE` |
| --- | --- |
| `stgregistry.suse.com/rancher/rancher:v2.14-head` | *unset* → Community |
| `stgregistry.suse.com/rancher/rancher:v2.14.5-rc2` | `prime` |
| `stgregistry.suse.com/rancher/rancher:v2.15.2-fbf2130-head` | `prime` |
| `docker.io/rancher/rancher:v2.15-head` | *unset* → Community |

Confirmed in production: nightly `metadata:v2.14-head` and `metadata:v2.13-head`
deploy from stgregistry and the deployed server reports **community**, while
`prime:v2.14` on `registry.rancher.com` reports **prime**. So within one
registry and one minor, the tag scheme decides: for 2.13 and 2.14 the
`vX.Y-head` branch head is Community while every alpha, rc and GA of the same
minor is Prime.

The charts say the same, and can be checked without registry credentials: a
Prime chart carries `prime` and `rancher-prime` keywords, a
`templates/scc-registration.yaml`, and a description naming SUSE Rancher Prime.

| Chart | `systemDefaultRegistry` | Prime markers |
| --- | --- | --- |
| `optimus/latest` `2.16.0-<sha>-head` | `stgregistry.suse.com` | yes |
| `optimus/server-charts/release-2.14` `2.14-<sha>-head` | `stgregistry.suse.com` | **no** |
| `releases.rancher.com/latest` `2.15.1-rc2` | *(empty)* -> Docker Hub | no |

Do not read a missing marker in an older chart as evidence, since it could be
the chart's age rather than its type. Comparing the **same version** from both
channels for 2.13.3-rc3, 2.14.3-rc1 and 2.15.1-rc2 gives markers present in the
Prime copy and absent from the Community copy in all three.

The first two are the point: same chart host, same image registry, opposite
build types. The tag scheme is what tracks it, and the per-minor head channels
publish the branch-head scheme:

| Tag shape | Reports | Chart repo |
| --- | --- | --- |
| `vX.Y-<sha>-head`, branch head | Community | `optimus/server-charts/release-X.Y` |
| `vX.Y.Z-<sha>-head`, one commit of the next patch | Prime | `optimus/server-charts/latest` |

The release team's `images-locations.md` splits these the same way, which is the
authority for the column above: 4.1 "Prime Head tags" is
`server-charts/latest`, and its worked example is a `2.15.1-<sha>` chart; 4.2
"Community head tags" is `server-charts/release-{major}.{minor}`, one repo per
release branch, which carries the `2.15-<sha>` shape. Both repos live in the
same bucket, so the bucket says nothing and the repo and tag shape say
everything.

That column is also not fixed: the release team is moving the floating
`vX.Y-head` tags onto Prime builds from 11 September 2026, so a tag that reports
Community today reports Prime afterwards. Nothing here needs changing on that
date, because the same question gets a different answer.

So the playbook asks the server:

```yaml
- name: Ask the deployed Rancher which build it is
  ansible.builtin.uri:
    url: "https://{{ rancher_host }}/rancherversion"
    validate_certs: false
    return_content: true
  register: _rancher_version_api
  failed_when: false
  retries: 5
  delay: 10
  until: _rancher_version_api.status | default(0) == 200
  when: _is_setup_or_test and rancher_host | default('', true) | length > 0
```

`until` is not decoration: `retries` and `delay` do nothing without it. The
server answers before it is ready to say what it is, so the task waits for a
200 rather than accepting the first response.

`RancherPrime` in the response decides the exclusion:

```text
prime      →  cypress_tags + "-@noPrime"
community  →  cypress_tags + "-@prime"
```

### Two Ansible traps in that task

Both were found on live runs and both are commented in place.

**The response is JSON under `Content-Type: text/plain`,** so the `uri` module
never populates `.json`. The body has to be parsed out of `.content`.

**Parsing has to happen in a single expression.** Assigning the body to an
intermediate variable hands it to Ansible's native-type conversion, which turns
it into a dict and makes every subsequent string operation fail with
`KeyError: slice(None, 1, None)`.

### The fallback

When there is no Rancher to ask, which is a `--tags test` run against an
existing cluster, the channel is consulted instead. That is what the playbook
did before, so that path keeps its previous answer rather than guessing. Which
source was used is reported, and recorded in `notification_values.txt` as
`RANCHER_BUILD_TYPE_SOURCE`:

```text
cypress_tags=@generic+-@prime+-@noVai (build type from the deployed Rancher)
cypress_tags=@generic+-@prime+-@noVai (build type from the channel, no Rancher to ask)
```

### `@bypass`

`@bypass` in `cypress_tags` means "take my expression exactly as written". The
marker is stripped and no exclusion is added. It is the escape hatch for running
a tag expression the resolver would otherwise modify.

### The empty-expression trap

`@cypress/grep` parses `+-@prime+-@noVai`, an expression with an empty positive
term, as matching *no test at all*. A run configured that way reports green
having executed nothing. The final `regex_replace` chain in the tag task
collapses the leading `+` for exactly this reason.

## Step 4: which UI {#which-ui}

A row picks a Rancher image. It does not pick a UI, and the two are not
automatically the same build.

`ui-offline-preferred` decides where the UI comes from. Its default, `dynamic`,
resolves through Rancher's `settings.IsRelease()`, which is
`!strings.Contains(serverVersion, "head") && regexp("^v[0-9]").Match(serverVersion)`:

| Build | `dynamic` serves | Pinned to the image? |
| --- | --- | --- |
| A release, `v2.15.1` | the UI the image embeds | yes |
| A head build, `v2.16.0-<sha>-head` | `ui-dashboard-index`, the CDN | **no** |

Both rows are measured, not read off the setting description: a GA deploy on the
default logged `ui-offline: dynamic` together with
`PROVENANCE ui build: 2.15.1 (from the image)`, and a head cluster on the same
default served the CDN.

So exactly the rows that most need reproducibility, the head rows, are the ones
the default leaves floating. `releases.rancher.com/dashboard/latest` is rebuilt
continuously and moves independently of the Rancher image, so the same image
tested twice can run two different UIs, and a failure can come from the asset
host rather than from Rancher.

Measured on a `v2.16.0-83a7758-head` cluster, flipping the setting and reading
the served HTML each way:

| Setting | Serves | Dashboard commit |
| --- | --- | --- |
| `dynamic` | `releases.rancher.com/dashboard/latest/` | `5c9f7a9` |
| `true` | `/dashboard/js/`, from the image | `df69324` |

Both are `master` commits, a day apart: the backend came from one commit and the
UI from another. The Jenkins jobs therefore set `ui_offline_preferred: "true"`,
which pins the pair. It changes nothing for a GA row, where `dynamic` already
serves the image.

`VERSION.txt` is written by `scripts/build-embedded` and `scripts/build-hosted`,
which the dashboard repository gained on `release-2.15`. From 2.15 onwards both
the image and the CDN carry it and the run names a commit. On `release-2.14` and
older neither script exists, so the image has no `VERSION.txt` and the CDN path
404s; the run falls back to hashing `index.html`, which is always present. The
hash is not a commit, but it changes whenever the UI does, so two runs naming
the same hash loaded the same build.

Nothing here is pinned to a minor. The CDN path comes from the cluster's
`ui-dashboard-index` setting, which each image carries, so it rotates on its
own: today 2.16 has no release branch and points at `latest`, which tracks
`master`; once `release-2.16` is cut the 2.16 images point there and the next
minor takes `latest`. A head build names a commit, a GA build names a version,
and a fallback names an index:

```text
PROVENANCE ui build:     ed075e6 (from the image)           # head, 2.15+
PROVENANCE ui build:     2.15.1 (from the image)            # GA, on the default
PROVENANCE ui build:     index 58443f752cdf (from the image) # pre-2.15
```

On an `existing` Rancher the line reads `not read (existing Rancher, deployed
outside this run)`: the UI is whatever the pre-existing deployment serves, which
this run did not choose.

Set to `false` to force the CDN, for example to reproduce a failure that only
appears with the published UI.

## Precedence {#precedence}

The resolver rewrites variables with `set_fact`. Ansible's precedence order puts
`set_fact` above `vars_files`, which is where `vars.yaml` is loaded, so the
rewrite wins on the normal path.

`set_fact` does **not** outrank `-e` extra-vars or task-level vars. A row that
silently kept its old channel would deploy the wrong build while reporting
success, so `resolve-channel.yml` asserts the rewrite took effect:

```yaml
- name: Confirm the Prime channel took effect
  ansible.builtin.assert:
    that:
      - rancher_helm_repo == _prime_pick.channel
      - rancher_image_tag | trim == _prime_pick.version
```

**This has direct consequences for testing.** A local reproduction that passes
configuration with `-e` is not reproducing the pipeline: the `-e` value cannot
be rewritten, so the resolver appears to do nothing and the run looks correct
when it is not. Production delivers configuration through `vars.yaml` via
`vars_files`. Reproduce it the same way.

## Verifying a change

The version gap matters. The runner image pins `ansible-core<2.17`, currently
**2.16.19**, while this repository's own `requirements.txt` pins
`ansible-core==2.21.3` for every other suite. That is five minor releases apart,
and it is deliberate: the collections this playbook needs, `community.docker <5`
and `community.crypto <3`, are the last that support 2.16. Both of the Ansible
traps above reproduce on 2.16 and not on newer. Verify in the image:

```bash
docker build -t dashboard-e2e-runner -f Dockerfile.quickstart .
docker run --rm -v "$PWD":/playbook -w /playbook \
  --entrypoint ansible-playbook dashboard-e2e-runner \
  --syntax-check -i localhost, dashboard-e2e-playbook.yml
```

Resolution itself can be exercised offline, because it only reads published
indexes. Include the real task files from a probe play, supply configuration
through `vars_files`, and loop over the rows you care about. That exercises the
shipped code rather than a copy of it.
