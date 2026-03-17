# rke2_setup

Prepares systems for RKE2 installation by installing required OS packages.

## Description

This role handles the initial system preparation for RKE2 installation. It detects the operating system and installs the necessary packages using the appropriate package manager. Firewall configuration is managed externally (e.g., via cloud provider security groups).

## Requirements

- Ansible 2.10 or higher
- Root/sudo access on target nodes
- Supported OS: SLES, SLE Micro, RHEL, CentOS, Ubuntu, Debian

## Role Variables

Variables defined in `defaults/main.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `rke2_required_packages` | `[tar, curl, wget]` | List of packages required for RKE2 installation |

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
```

## OS Support

This role automatically detects the operating system and uses the appropriate package manager:

- **SLES/openSUSE**: Uses `zypper`
- **RHEL/CentOS**: Uses `yum`
- **Debian/Ubuntu**: Uses `apt`

## Tasks Performed

1. Display OS information (distribution, version, family)
2. Install required packages using the OS-specific package manager (zypper/yum/apt)
3. Log setup completion

> **Note:** Firewall configuration is not managed by this role. Port access should be controlled via cloud provider security groups or an external firewall role.

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
