# suse_selinux_policy

Installs or verifies the Rancher SELinux policy package for RKE2 or K3s on
SELinux-enabled SUSE hosts.

## Behavior

The role does nothing on non-SUSE hosts, when SELinux is disabled, or when
`suse_selinux_policy_install` is false. Otherwise it checks that the product
package and SELinux module are both present.

In online mode, a missing policy is installed from the operator-managed Rancher
common repository whose alias matches the resolved channel. Repository aliases
are discovered in every `/etc/zypp/repos.d/*.repo` file, regardless of filename.
If the requested alias does not exist, the role creates a channel-specific file
from the configured RPM site. Other channel repositories may coexist, but the
install is explicitly scoped to the requested alias with `zypper --from`.
Existing repository files are never deleted, and duplicate aliases fail with a
clear error.

In offline mode, the role never configures or contacts an RPM repository. The
policy package, its dependencies, and the loaded module must already be present;
otherwise the role fails before RKE2 or K3s is enabled.

On transactional hosts, installation runs through `transactional-update` and
reboots to activate the new snapshot. The role temporarily stops
`transactional-update.timer` while installing and restores its previous active
state afterward. Set `suse_disable_update_timer` to keep the timer disabled.

## Variables

| Variable | Default | Description |
|---|---|---|
| `suse_selinux_product` | `""` | Product prefix: `rke2` or `k3s` |
| `suse_selinux_channel` | `stable` | Product channel used to select the common repository |
| `suse_selinux_rpm_site` | `rpm.rancher.io` | RPM host for stable/latest channels |
| `suse_selinux_testing_rpm_site` | `rpm-testing.rancher.io` | RPM host for the testing channel |
| `suse_selinux_installer_repo_file` | `""` | Installer-managed repository file that may already contain the common alias |
| `suse_selinux_policy_install` | `true` | Enable policy installation or verification |
| `suse_selinux_offline` | `false` | Verify a preinstalled policy without configuring or contacting repositories |
| `suse_disable_update_timer` | `false` | Keep `transactional-update.timer` disabled after the run |

## Example

```yaml
- name: Ensure the RKE2 SELinux policy
  ansible.builtin.include_role:
    name: suse_selinux_policy
  vars:
    suse_selinux_product: rke2
    suse_selinux_channel: stable
    suse_selinux_offline: "{{ install_method == 'airgap' }}"
```
