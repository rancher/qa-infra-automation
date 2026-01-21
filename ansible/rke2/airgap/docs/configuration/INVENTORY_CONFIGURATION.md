# Inventory Configuration Guide

This guide explains how to configure the Ansible inventory for RKE2 airgap deployments with parameterized bastion host settings.

## Parameterized Configuration

The inventory now uses variables to make bastion host configuration flexible and reusable:

### Global Variables

```yaml
all:
  vars:
    # Global SSH configuration
    ssh_private_key_file: "~/.ssh/id_rsa"
    bastion_user: "ubuntu"
    bastion_host: "<BASTION_PUBLIC_DNS_NAME>"
```

### Key Benefits

1. **Single Point of Configuration**: Change bastion details in one place
2. **Consistency**: All SSH proxy commands use the same bastion configuration
3. **Reusability**: Easy to adapt for different environments

### **IMPORTANT: SSH Key Path Configuration**

**WARNING: Use absolute paths for SSH keys** to avoid tilde (`~`) expansion issues:

```yaml
# CORRECT - Absolute path
ssh_private_key_file: "/home/username/.ssh/id_rsa"

# INCORRECT - Tilde expansion can cause issues
ssh_private_key_file: "~/.ssh/id_rsa"
```

The tilde (`~`) can be expanded differently depending on the execution context, leading to SSH key not found errors.

1. **Maintainability**: No hardcoded values scattered throughout the inventory

## SSH Key Setup

Before running any RKE2 deployment playbooks, you must ensure SSH keys are properly distributed to all hosts, especially the bastion host.

### Prerequisites

1. **SSH Key Pair**: Ensure you have an SSH key pair on your Ansible control node
2. **Bastion Access**: The bastion host must be directly accessible from your control node
3. **Key Distribution**: SSH keys must be copied to the bastion host for proxy connections

### Setup SSH Keys

Run the SSH key setup playbook first:

```bash
# Setup SSH keys on all hosts
ansible-playbook -i inventory/inventory.yml playbooks/deploy/setup-ssh-keys.yml
```

This playbook will:

- Copy your SSH private key to the bastion host with the correct filename
- Set up proper permissions (600 for private key, 644 for public key)
- Create backward compatibility symlinks
- Verify SSH connectivity between hosts

### SSH Key File Structure

After running the setup, each host will have:

```
~/.ssh/
├── id_rsa          # Your actual SSH private key
├── id_rsa.pub      # Your actual SSH public key
├── id_rsa -> id_rsa     # Symlink for compatibility
├── id_rsa.pub -> id_rsa.pub  # Symlink for compatibility
└── authorized_keys               # Contains your public key
```

### Troubleshooting SSH Issues

If you encounter SSH connectivity issues:

1. **Verify key permissions**:

   ```bash
   ansible all -i inventory/inventory.yml -m shell -a "ls -la ~/.ssh/"
   ```

2. **Test bastion connectivity**:

   ```bash
   ansible bastion -i inventory/inventory.yml -m ping
   ```

3. **Test airgap node connectivity**:

   ```bash
   ansible airgap_nodes -i inventory/inventory.yml -m ping
   ```

4. **Manual SSH test**:

   ```bash
   # Test direct bastion connection
   ssh -i /home/dnewman/.ssh/id_rsa ubuntu@<BASTION_PUBLIC_DNS_NAME>

   # Test proxy connection to airgap node
   ssh -i /home/dnewman/.ssh/id_rsa -o ProxyCommand='ssh -W %h:%p -i /home/dnewman/.ssh/id_rsa ubuntu@<BASTION_PUBLIC_DNS_NAME>' ubuntu@172.31.4.247
   ```

## Configuration Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `ssh_private_key_file` | Path to SSH private key | `~/.ssh/id_rsa` |
| `bastion_user` | Username for bastion host | `ubuntu` |
| `bastion_host` | Bastion host address | `<BASTION_PUBLIC_DNS_NAME>` |

## Bastion Host Configuration

```yaml
bastion:
  hosts:
    bastion-node:
      ansible_host: "{{ bastion_host }}"
      ansible_user: "{{ bastion_user }}"
      ansible_ssh_common_args: "-A -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
```

## Airgap Nodes Configuration

```yaml
airgap_nodes:
  vars:
    # SSH proxy configuration for all airgap nodes
    ansible_user: "ubuntu"
    ansible_ssh_common_args: "-A -o ProxyCommand='ssh -A -W %h:%p -i {{ ssh_private_key_file }} {{ bastion_user }}@{{ bastion_host }}' -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    bastion_ip: "{{ bastion_host }}"

  hosts:
    rke2-server-0:
      ansible_host: "<AIRGAP_NODE_PRIVATE_IP>"
    rke2-server-1:
      ansible_host: "<AIRGAP_NODE_PRIVATE_IP>"
    rke2-server-2:
      ansible_host: "<AIRGAP_NODE_PRIVATE_IP>"
```

## Customizing for Your Environment

To adapt this inventory for your environment, simply update the global variables:

```yaml
all:
  vars:
    # Update these values for your environment
    ssh_private_key_file: "/path/to/your/private/key"
    bastion_user: "your-bastion-user"
    bastion_host: "your-bastion-host.example.com"
```

## SSH Proxy Command Explanation

The parameterized SSH proxy command:

```bash
-o ProxyCommand='ssh -W %h:%p -i {{ ssh_private_key_file }} {{ bastion_user }}@{{ bastion_host }}'
```

Expands to:

```bash
-o ProxyCommand='ssh -W %h:%p -i ~/.ssh/id_rsa ubuntu@<BASTION_PUBLIC_DNS_NAME>'
```

Where:

- `%h:%p` = target host and port (airgap node)
- `-i {{ ssh_private_key_file }}` = SSH private key path
- `{{ bastion_user }}@{{ bastion_host }}` = bastion connection details

## Environment-Specific Overrides

You can override variables for specific environments using inventory/group_vars or host_vars:

### inventory/group_vars/all.yml

```yaml
# Production environment
ssh_private_key_file: "/etc/ansible/keys/prod-key"
bastion_user: "ec2-user"
bastion_host: "prod-bastion.company.com"
```

### inventory/group_vars/staging.yml

```yaml
# Staging environment
bastion_host: "staging-bastion.company.com"
```

## Validation

To verify your configuration:

```bash
# Test bastion connectivity
ansible bastion -i inventory/inventory.yml -m ping

# Test airgap node connectivity through bastion
ansible airgap_nodes -i inventory/inventory.yml -m ping

# Display resolved variables
ansible-inventory -i inventory/inventory.yml --list
```

## Troubleshooting

### Common Issues

1. **SSH Key Path**: Ensure the SSH key path is accessible from the Ansible control node
2. **Bastion Connectivity**: Verify the bastion host is reachable and SSH key works
3. **Variable Resolution**: Check that variables are properly resolved using `ansible-inventory --list`

### Debug Commands

```bash
# Show resolved inventory
ansible-inventory -i inventory/inventory.yml --list --yaml

# Test SSH connectivity
ansible all -i inventory/inventory.yml -m setup --limit bastion
ansible all -i inventory/inventory.yml -m setup --limit airgap_nodes
```

This parameterized approach makes the inventory much more maintainable and adaptable to different environments while ensuring consistency across all SSH proxy configurations.
