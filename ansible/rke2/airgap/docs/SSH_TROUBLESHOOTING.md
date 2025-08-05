# SSH Connectivity Troubleshooting Guide

## Problem Summary
The private_registry role was failing with "Connection to UNKNOWN port 65535 timed out" errors when using `delegate_to` tasks from the bastion host to airgap nodes.

## Root Cause
The issue was caused by a conflict between SSH proxy configuration and Ansible's `delegate_to` mechanism:

1. **Local machine → airgap nodes**: Uses SSH proxy through bastion (correct)
2. **Bastion host → airgap nodes**: Should use direct SSH connection (was incorrectly trying to proxy through itself)


## Testing Steps

### Step 1: Test Basic Connectivity
```bash
# Test the connectivity fix
ansible-playbook -i inventory/inventory.yml test-ssh-connectivity.yml
```

### Step 3: Manual SSH Tests
```bash
# Test direct SSH from your local machine to bastion
ssh -i ~/.ssh/id_rsa ubuntu@<BASTION_PUBLIC_DNS_NAME>

# Test SSH proxy from local machine to airgap node
ssh -o ProxyCommand='ssh -W %h:%p -i ~/.ssh/id_rsa ubuntu@<BASTION_PUBLIC_DNS_NAME>' -i ~/.ssh/id_rsa ubuntu@<AIRGAP_NODE_PRIVATE_IP>
```

## Network Architecture

```
[Local Machine] 
    ↓ (SSH + Key)
[Bastion Host: <BASTION_PUBLIC_DNS_NAME>]
    ↓ (Direct SSH + Key)
[Airgap Nodes: 172.31.4.230, 172.31.4.32, 172.31.11.187]
```

## Key Points

1. **From Local Machine**: Use SSH proxy through bastion
2. **From Bastion Host**: Use direct SSH connection (no proxy)
3. **SSH Key**: Same key (`~/.ssh/id_rsa`) used for all connections
4. **Template Variables**: Avoid using Jinja2 templates in `ansible_ssh_common_args` - use literal values

## Verification Commands

After applying the fixes, verify with:

```bash
# Check inventory syntax
ansible-inventory -i inventory/inventory.yml --list

# Test connectivity to all hosts
ansible -i inventory/inventory.yml all -m ping


```

## Alternative Solutions (if needed)

If the current fix doesn't work, consider these alternatives:

### Option 1: Use add_host for Dynamic Inventory
Create separate host entries for delegate_to scenarios.

### Option 2: Use SSH Config File
Create a proper SSH config file instead of command-line arguments.

### Option 3: Split the Role
Separate the registry setup from the airgap node configuration.