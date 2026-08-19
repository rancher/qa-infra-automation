# airgap_rke2_ui_plugin_mirror

Mirrors [`rancher/ui-plugin-charts`](https://github.com/rancher/ui-plugin-charts) on the
airgap **bastion** host and serves it over HTTP, so an airgapped Rancher server can install
UI extensions (NeuVector first) with **no outbound `github.com` egress**.

> **Requirements:** an Ubuntu/Debian bastion. The Apache wiring (package
> install, `a2enconf`/`conf-available` layout, `/usr/lib/git-core/git-http-backend`
> path, `${APACHE_LOG_DIR}`) is Debian-family specific; the role fails fast with
> a clear message on other families. SLES support is planned as a follow-up.

## Why

NeuVector's UI extension is installed via a **git-based** `ClusterRepo`
(`Spec.GitRepo` / `Spec.GitBranch`). Rancher's catalog controller `git clone`s that URL
**from inside the Rancher server pod** in the `local` cluster. In airgap the server cannot
reach `github.com`, so the extension is normally skipped. The bastion has internet access
and is reachable from the airgap cluster, which makes it the natural mirror host.

## How it works

The role runs on `hosts: bastion` and is **gated by `enable_ui_plugin_mirror`** (default
`false`, so ordinary airgap runs are unaffected):

1. Ensures `git` and `apache2` are installed.
2. `git clone --mirror` of the upstream repo into `ui_plugin_mirror_dest`
   (`/srv/git/ui-plugin-charts.git` by default). On re-run it syncs via
   `git remote update --prune`, so it stays current and never fails when the mirror
   already exists.
3. Points the mirror's `HEAD` at `ui_plugin_mirror_branch` (`git symbolic-ref`, only when
   it differs) so clones check out that branch.
4. Serves the bare repo over **smart HTTP** via Apache + `git-http-backend` (prefork MPM
   + `mod_cgi`), configured as `/etc/apache2/conf-available/ui-plugin-mirror.conf` and
   listening on `ui_plugin_mirror_listen:ui_plugin_mirror_port`. A system-wide
   `safe.directory *` lets the web-server user (`www-data`) serve the root-owned repo.
5. Exposes `ui_plugin_mirror_url`
   (`http://<bastion>:<port>/ui-plugin-charts.git`) for consumers.

The repo is served at `/<basename>` because `GIT_PROJECT_ROOT` is the **parent** of
`ui_plugin_mirror_dest`.

> **Transport — smart HTTP is required.** Rancher's catalog controller clones with
> `--depth=1` (shallow); dumb HTTP (`python3 -m http.server`) cannot do shallow clones
> ("dumb http transport does not support shallow capabilities"). Smart HTTP via
> `git-http-backend` supports shallow clones and has been verified end-to-end from an
> airgap node (`git clone --depth=1` succeeds). Note: `mod_cgid` under Apache's event MPM
> fails to reach its CGI daemon for `git-http-backend`, so the role switches to the
> **prefork MPM + `mod_cgi`**.

## Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `enable_ui_plugin_mirror` | `false` | Opt-in gate. Default off so other airgap runs are unaffected. |
| `ui_plugin_mirror_src` | `https://github.com/rancher/ui-plugin-charts` | Upstream repo to mirror. |
| `ui_plugin_mirror_branch` | `main` | Branch the catalog clones; the role fails fast if it is absent. |
| `ui_plugin_mirror_dest` | `/srv/git/ui-plugin-charts.git` | Bare mirror path on the bastion. The server roots at its parent. |
| `ui_plugin_mirror_listen` | `0.0.0.0` | HTTP bind address. |
| `ui_plugin_mirror_port` | `8080` | HTTP port. |
| `ui_plugin_mirror_host` | (auto: bastion private IPv4) | Host used in the published URL. Defaults to the bastion's primary private IP (`ansible_default_ipv4.address`) so airgap nodes reach it without relying on VPC public-DNS resolution. Override to pin a DNS name / other interface. |

## Usage

```bash
# Standalone (manual / independent use)
make ui-plugin-mirror ENV=airgap

# As part of the full airgap pipeline (opt-in via the Makefile flag):
make all ENV=airgap ENABLE_UI_PLUGIN_MIRROR=yes

# Or via the airgap deploy playbook — set the gate in the job's ANSIBLE_VARIABLES
# and it is stood up automatically by the registry step:
make registry ENV=airgap EXTRA_VARS="enable_ui_plugin_mirror=true"
```

Then point the NeuVector UI extension at the mirror. In `cattle-config.yaml`
(`CATTLE_TEST_CONFIG`), set the following under `neuvectorTest` (the playbook prints this
snippet with the computed URL/branch at the end of the run):

```yaml
neuvectorTest:
  uiPluginChartsURL: "http://<bastion>:8080/ui-plugin-charts.git"
  uiPluginChartsBranch: "main"
  skipUIExtension: false   # must be false; defaults to true in airgap, which skips the install
```

And confirm the mirror is cloneable from an airgap node / Rancher server pod:

```bash
git clone http://<bastion>:8080/ui-plugin-charts.git
```

## Related

- Issue rancher/qa-infra-automation#179 — this role.
- rancher/tests#821 — Slice 6 (tracking); rancher/tests#807 consumes the mirror via
  `ANSIBLE_VARIABLES` + `CATTLE_TEST_CONFIG`.
