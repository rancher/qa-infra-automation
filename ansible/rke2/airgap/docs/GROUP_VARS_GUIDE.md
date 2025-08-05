# Group Variables Configuration Guide

This guide explains how to configure the RKE2 airgap deployment using Ansible group_vars instead of environment variables.

## Directory Structure

```
ansible/rke2/airgap/
├── group_vars/
│   ├── all.yml           # Global variables for all hosts
│   ├── bastion.yml       # Variables specific to bastion hosts
│   └── airgap_nodes.yml  # Variables specific to airgap nodes
├── inventory.yml         # Host inventory
└── rke2-registry-distribution-playbook.yml
```

## Quick Start

### 1. Configure Your Registry Settings

Edit `group_vars/all.yml`:

```yaml
# External Registry (replace with your values)
external_registry_url: "harbor.company.com"
external_registry_username: "robot-account"
external_registry_password: "your-robot-token"

# Local Registry Credentials
registry_username: "admin"
registry_password: "secure-password-123"

# RKE2 Version
rke2_version: "v1.24.1+rke2r1"
```

### 2. Customize Bastion Settings (Optional)

Edit `group_vars/bastion.yml` if you need to change:
- Registry port (default: 5000)
- Storage directories
- SSL certificate details
- Performance settings

### 3. Customize Airgap Node Settings (Optional)

Edit `group_vars/airgap_nodes.yml` if you need to change:
- RKE2 directories
- Container runtime settings
- Node labels/taints
- Resource limits

### 4. Run the Playbook

```bashansible-playbook -i inventory.yml rke2-registr
y-distribution-playbook.yml
```

## Configuration Examples

### Basic Configuration

Minimal configuration in `group_vars/all.yml`:

```yaml
# Required settings
external_registry_url: "your-registry.com"
external_registry_username: "username"
external_registry_password: "password"
registry_username: "admin"
registry_password: "admin123"
rke2_version: "v1.24.1+rke2r1"
```

### Production Configuration

Production-ready configuration with security:

```yaml
# group_vars/all.yml
external_registry_url: "harbor.prod.company.com"
external_registry_username: "{{ vault_external_registry_username }}"
external_registry_password: "{{ vault_external_registry_password }}"
external_registry_verify_ssl: true

registry_username: "{{ vault_registry_username }}"
registry_password: "{{ vault_registry_password }}"
registry_auth: true

rke2_version: "v1.24.1+rke2r1"
installation_method: "registry_distribution"

# Custom images for your applications
custom_images:
  - "harbor.prod.company.com/apps/frontend:v1.2.3"
  - "harbor.prod.company.com/apps/backend:v1.2.3"
  - "harbor.prod.company.com/monitoring/prometheus:v2.40.0"

# Security settings
disable_components:
  - rke2-snapshot-controller
  - rke2-snapshot-controller-crd

enable_audit_log: true
audit_log_maxage: 30
```

### Development Configuration

Development environment with relaxed security:

```yaml
# group_vars/all.yml
external_registry_url: "registry.dev.company.com"
external_registry_username: "dev-user"
external_registry_password: "dev-password"
external_registry_verify_ssl: false  # Self-signed certs

registry_username: "admin"
registry_password: "admin"
registry_auth: false  # No auth for dev

rke2_version: "v1.24.1+rke2r1"

# Development-specific settings
log_level: "debug"
enable_audit_log: false
cleanup_temp_files: false  # Keep files for debugging
```

## Security Best Practices

### Using Ansible Vault

1. **Encrypt sensitive variables**:
   ```bash
   # Create encrypted vars file
   ansible-vault create group_vars/vault.yml
   ```

2. **Add sensitive variables to vault.yml**:
   ```yaml
   vault_external_registry_username: "real-username"
   vault_external_registry_password: "real-password"
   vault_registry_username: "real-admin"
   vault_registry_password: "real-secure-password"
   ```

3. **Reference vault variables in all.yml**:
   ```yaml
   external_registry_username: "{{ vault_external_registry_username }}"
   external_registry_password: "{{ vault_external_registry_password }}"
   registry_username: "{{ vault_registry_username }}"
   registry_password: "{{ vault_registry_password }}"
   ```

4. **Run with vault password**:
   ```bash
   ansible-playbook -i inventory.yml rke2-registry-distribution-playbook.yml --ask-vault-pass
   ```

### Environment-Specific Configurations

Create separate configurations for different environments:

```
group_vars/
├── all.yml                    # Common settings
├── bastion.yml               # Bastion settings
├── airgap_nodes.yml          # Node settings
├── production/
│   ├── all.yml               # Production overrides
│   └── vault.yml             # Production secrets
├── staging/
│   ├── all.yml               # Staging overrides
│   └── vault.yml             # Staging secrets
└── development/
    └── all.yml               # Development overrides
```

Run with environment-specific vars:
```bash
# Production
ansible-playbook -i inventory.yml rke2-registry-distribution-playbook.yml \
  -e @group_vars/production/all.yml --vault-password-file .vault_pass

# Staging
ansible-playbook -i inventory.yml rke2-registry-distribution-playbook.yml \
  -e @group_vars/staging/all.yml --ask-vault-pass
```

## Variable Precedence

Ansible variable precedence (highest to lowest):
1. Command line `-e` variables
2. Task variables
3. Block variables
4. Role variables
5. Play variables
6. Host variables
7. **Group variables** ← Our configuration
8. Inventory variables
9. Role defaults

## Troubleshooting

### Check Variable Values

```bash
# Debug variables for a specific host
ansible -i inventory.yml bastion-node -m debug -a "var=external_registry_url"

# Debug all variables for a host
ansible -i inventory.yml bastion-node -m debug -a "var=hostvars[inventory_hostname]"
```

### Validate Configuration

```bash
# Check syntax
ansible-playbook -i inventory.yml rke2-registry-distribution-playbook.yml --syntax-check

# Dry run
ansible-playbook -i inventory.yml rke2-registry-distribution-playbook.yml --check

# List tasks
ansible-playbook -i inventory.yml rke2-registry-distribution-playbook.yml --list-tasks
```

### Common Issues

1. **Variable not found**: Check spelling and file location
2. **Vault decryption failed**: Verify vault password
3. **Template errors**: Check Jinja2 syntax in variable references
4. **Permission denied**: Ensure proper file permissions on group_vars files

## Migration from Environment Variables

If you have existing environment variables, convert them:

```bash
# Old way
export EXTERNAL_REGISTRY_URL="harbor.company.com"
export EXTERNAL_REGISTRY_USERNAME="user"

# New way - add to group_vars/all.yml
external_registry_url: "harbor.company.com"
external_registry_username: "user"
```

The group_vars approach is more maintainable, version-controllable, and follows Ansible best practices.