# rke2_setup

Prepares systems for RKE2 installation by installing required packages and configuring firewall.

## Description

This role handles the initial system preparation for RKE2 installation. It detects the operating system, installs necessary packages, and ensures firewalld is available and running.

## Requirements

- Ansible 2.10 or higher
- Root/sudo access on target nodes
- Supported OS: SLES, SLE Micro, RHEL, CentOS, Ubuntu, Debian

## Role Variables

Variables defined in `defaults/main.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `rke2_required_packages` | `[tar, curl, wget]` | List of packages required for RKE2 installation |
| `rke2_firewall_service` | `firewalld` | Firewall service name |
| `rke2_firewall_state` | `started` | Desired firewall service state |
| `rke2_firewall_enabled` | `true` | Enable firewall on boot |

## Dependencies

None

## Example Playbook

```yaml
---
- name: Setup system for RKE2
  hosts: all
  become: true
  roles:
    - rke2_setup
```

With custom variables:

```yaml
---
- name: Setup system for RKE2
  hosts: all
  become: true
  roles:
    - role: rke2_setup
      vars:
        rke2_required_packages:
          - tar
          - curl
          - wget
          - jq
        rke2_firewall_enabled: false
```

## OS Support

This role automatically detects the operating system and uses the appropriate package manager:

- **SLES/openSUSE**: Uses `zypper`
- **RHEL/CentOS**: Uses `yum`
- **Debian/Ubuntu**: Uses `apt`

## Tasks Performed

1. Display OS information
2. Install required packages (tar, curl, wget) using OS-specific package manager
3. Check if firewalld is available
4. Install firewalld if not present
5. Enable and start firewalld service

## Testing

```bash
# Test the role syntax
ansible-playbook --syntax-check -i inventory.yml playbook.yml

# Run in check mode (dry run)
ansible-playbook --check -i inventory.yml playbook.yml

# Run the playbook
ansible-playbook -i inventory.yml playbook.yml
```

## Author

SUSE Rancher QA Team (@rancher/qa-pit-crew)

## License

Apache 2.0
