# SSH Connectivity Troubleshooting Guide

## Testing Steps

### Step 1: Test Basic Connectivity
```bash
# Test the connectivity fix
ansible-playbook -i inventory/inventory.yml playbooks/debug/test-ssh-connectivity.yml
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