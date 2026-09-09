# airgap_rke2_charts_mirror

Mirrors `rancher/charts` (`https://git.rancher.io/charts`) on the airgap
bastion and serves it over git smart-HTTP so an airgapped Rancher server's
catalog can resolve `rancher-charts` charts (rancher-monitoring,
rancher-alerting-drivers, ...) with **no git.rancher.io egress**.

The companion task in `rancher-helm-deploy-playbook.yml` repoints the
`rancher-charts` ClusterRepo at the mirror URL after Rancher is up (gated on
the same `enable_charts_mirror` flag), so no DNS or TLS impersonation of
`git.rancher.io` is needed: the ClusterRepo simply clones from the bastion.

## Why

Without a mirror, an airgap Rancher either cannot sync `rancher-charts` at all
or depends on a stale ad-hoc copy. A trimmed mirror (latest version only)
additionally breaks the rancher/tests validation suites that need:

| Requirement | Consumer |
|---|---|
| `rancher-alerting-drivers` present in the index | `TestAlertingTestSuite` |
| at least 2 `rancher-monitoring` versions | `TestUpgradeMonitoringChart` |

This role mirrors the **whole requested release branch**, which carries every
chart and every version published for that Rancher minor, satisfying both.

## Usage

```
make charts-mirror ENV=airgap                      # standalone
make all ENV=airgap ENABLE_CHARTS_MIRROR=yes       # wired into full setup
```

The Rancher deploy step picks the mirror up automatically when the bastion
fact `/etc/ansible/facts.d/charts_mirror.fact` exists and repoints the
`rancher-charts` ClusterRepo at it.

## Variables

See `defaults/main.yml`. Highlights:

- `charts_mirror_branch` (default `release-v2.15`): must match the deployed
  Rancher minor. Only this branch is fetched; a full all-branch mirror is
  multi-GB of history the catalog never serves.
- `charts_mirror_dest` (default `/srv/git/charts.git`): must share a parent
  with `ui_plugin_mirror_dest` (default `/srv/git`) when the ui-plugin mirror
  vhost is enabled; the role asserts this and fails otherwise.
- `charts_mirror_host` (default: auto-detected bastion private IPv4): the
  address published in the mirror URL the catalog clones.

## Notes

- Requires an Ubuntu/Debian bastion (Apache layout, `git-http-backend` path).
  The bastion needs egress to `git.rancher.io` for the initial fetch/refresh
  (it is the bridge host; same requirement as the ui-plugin mirror).
- Rancher seeds the default `rancher-charts` ClusterRepo; repointing its
  `gitRepo` is supported (it is an ordinary ClusterRepo), but a Rancher
  upgrade may re-seed it, after which the deploy playbook step should be
  re-run (idempotent).
- Security group: cluster nodes need TCP access to the mirror port (default
  8080, shared with the ui-plugin mirror vhost).
