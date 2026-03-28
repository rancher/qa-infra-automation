# wait_for_ssh

Waits for SSH connection to be established before proceeding with playbook execution.

This role is useful when provisioning new infrastructure (e.g., via Terraform/OpenTofu) where instances may exist but SSH daemon is not yet ready.

## Requirements

None. Uses Ansible's built-in `wait_for_connection` module.

## Role Variables

All variables are optional with sensible defaults:

| Variable | Default | Description |
|----------|---------|-------------|
| `wait_for_ssh_timeout` | 300 | Maximum time to wait for SSH (seconds) |
| `wait_for_ssh_sleep` | 5 | Sleep between connection attempts (seconds) |
| `wait_for_ssh_connect_timeout` | 10 | Timeout for each connection attempt (seconds) |
| `wait_for_ssh_retries` | 3 | Number of retries if connection fails |
| `wait_for_ssh_retry_delay` | 10 | Delay between retry attempts (seconds) |

## Example Usage

### As first role in a play

```yaml
- hosts: all
  gather_facts: false
  roles:
    - wait_for_ssh
    - setup
    - k3s_install
```

### With custom timeout

```yaml
- hosts: all
  gather_facts: false
  vars:
    wait_for_ssh_timeout: 600  # Wait up to 10 minutes
  roles:
    - wait_for_ssh
```

### As a pre_task

```yaml
- hosts: all
  gather_facts: false
  pre_tasks:
    - name: Wait for SSH
      ansible.builtin.include_role:
        name: wait_for_ssh
  roles:
    - setup
```

## Dependencies

None
