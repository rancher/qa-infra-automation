# rke2_install

Installs RKE2 (Rancher Kubernetes Engine 2) binary and container images.

## Description

This role downloads and installs RKE2 on target nodes. It supports both online (internet-connected) and airgap (offline) installation methods, version pinning, and automatic service configuration.

## Requirements

- Ansible 2.10 or higher
- Root/sudo access on target nodes
- System prepared with required packages (via rke2_setup role)
- Configuration generated (via rke2_config role)

For online installation:
- Internet connectivity to get.rke2.io

For airgap installation:
- RKE2 tarball available on target or control node
- RKE2 images tarball available
- RKE2 install script available

## Role Variables

Variables defined in `defaults/main.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `rke2_version` | `""` (latest stable) | Specific RKE2 version to install |
| `rke2_install_method` | `online` | Installation method: `online` or `airgap` |
| `rke2_install_script_url` | `https://get.rke2.io` | URL to download install script |
| `rke2_channel` | `stable` | Release channel: `stable`, `latest`, or `testing` |
| `rke2_bin_dir` | `/usr/local/bin` | Directory for RKE2 binary |
| `rke2_data_dir` | `/var/lib/rancher/rke2` | RKE2 data directory |
| `rke2_airgap_tarball` | `""` | Path to RKE2 tarball for airgap install |
| `rke2_airgap_images_tarball` | `""` | Path to container images tarball |
| `rke2_airgap_install_script` | `""` | Path to install script for airgap |
| `rke2_start_on_boot` | `true` | Enable RKE2 service to start on boot |
| `rke2_start_after_install` | `false` | Start RKE2 immediately after install |

## Dependencies

Recommended to run after:
- `rke2_setup` - System preparation
- `rke2_config` - Configuration generation

## Example Playbook

### Online Installation (Default)

```yaml
---
- name: Install RKE2 online
  hosts: all
  become: true
  roles:
    - rke2_install
```

### Install Specific Version

```yaml
---
- name: Install RKE2 v1.28.5+rke2r1
  hosts: all
  become: true
  roles:
    - role: rke2_install
      vars:
        rke2_version: v1.28.5+rke2r1
```

### Airgap Installation

```yaml
---
- name: Install RKE2 airgap
  hosts: all
  become: true
  roles:
    - role: rke2_install
      vars:
        rke2_install_method: airgap
        rke2_airgap_tarball: /tmp/rke2.linux-amd64.tar.gz
        rke2_airgap_images_tarball: /tmp/rke2-images.linux-amd64.tar.zst
        rke2_airgap_install_script: /tmp/install.sh
```

### Install and Start Immediately

```yaml
---
- name: Install and start RKE2
  hosts: all
  become: true
  roles:
    - role: rke2_install
      vars:
        rke2_start_after_install: true
```

## Installation Methods

### Online Installation

The online method:
1. Downloads the official install script from `get.rke2.io`
2. Executes the script with specified version/channel
3. Installs RKE2 server (for control-plane/etcd) or agent (for workers)
4. Enables the systemd service

**Advantages:**
- Simple and quick
- Always gets latest patches
- No pre-download required

**Requirements:**
- Internet connectivity
- Access to GitHub releases

### Airgap Installation

The airgap method:
1. Extracts RKE2 binary from tarball
2. Places container images in data directory
3. Runs the install script to set up systemd service
4. Enables the service

**Advantages:**
- Works in offline environments
- Repeatable installations
- No external dependencies

**Requirements:**
- Pre-downloaded tarballs available on target or Ansible control node
- Sufficient disk space for images (~2-4 GB)

## Version Pinning

To install a specific RKE2 version:

```yaml
rke2_version: v1.28.5+rke2r1
```

To install from a different channel:

```yaml
rke2_channel: latest  # or testing
```

Leave `rke2_version` empty to install the latest from the selected channel.

## Node Type Detection

The role automatically determines whether to install RKE2 server or agent based on:
- `rke2_node_role` (typically `master` for first node)
- `node_roles` containing `cp` or `etcd`

**Server installation** if:
- `rke2_node_role == 'master'` OR
- `'cp' in node_roles` OR
- `'etcd' in node_roles`

**Agent installation** otherwise (worker nodes)

## Service Management

By default, the role:
- Enables the RKE2 service to start on boot (`rke2_start_on_boot: true`)
- Does NOT start the service immediately (`rke2_start_after_install: false`)

This allows the `rke2_cluster` role to handle proper startup sequencing (master first, then servers, then agents).

To start immediately after installation:

```yaml
rke2_start_after_install: true
```

## Idempotency

The role is idempotent:
- Checks if RKE2 is already installed
- Only installs if not present or version mismatch
- Safe to run multiple times

## Post-Installation

After running this role:
- RKE2 binary is available at `/usr/local/bin/rke2`
- Systemd service is created (rke2-server or rke2-agent)
- Service is enabled but not started
- Container images are available (airgap) or will be downloaded on first start (online)

Run the `rke2_cluster` role next to start services and form the cluster.

## Testing

```bash
# Verify binary is installed
ansible all -i inventory.yml -m shell -a "rke2 --version"

# Check service status
ansible all -i inventory.yml -m shell -a "systemctl status rke2-server" -b

# Verify images (airgap)
ansible all -i inventory.yml -m shell -a "ls -lh /var/lib/rancher/rke2/agent/images/" -b
```

## Troubleshooting

**Problem:** Install script fails with connection timeout
**Solution:** Check internet connectivity or use airgap method

**Problem:** Service fails to start after installation
**Solution:** Check logs with `journalctl -u rke2-server -xe`, verify configuration in `/etc/rancher/rke2/config.yaml`

**Problem:** Version mismatch after installation
**Solution:** Ensure `rke2_version` matches desired version format (e.g., `v1.28.5+rke2r1` not `v1.28.5`)

## License

Apache 2.0
