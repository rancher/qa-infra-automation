# Rancher Auth Role

Generate Rancher API tokens and manage authentication for automation and CI/CD pipelines.

## Features

- **Token Authentication**: Authenticate with Rancher using username/password
- **Token TTL**: Configure token expiration (or create non-expiring tokens)
- **Multiple Output Formats**: Plain token, JSON, or tfvars format
- **Cattle Config Integration**: Automatically update cattle-config.yaml
- **First Login Flow**: Optionally set permanent password after bootstrap
- **Environment Variable Support**: Configure via env vars for CI/CD convenience

## How It Works

This role creates a Rancher API token through a multi-step process:

1. **Login** -- Authenticates with username/password to get a temporary session token (~15h TTL)
2. **Token creation** -- Uses the session token to create a persistent API token with your configured TTL
3. **Cleanup** -- Deletes the temporary session token so only the persistent token remains

Only the persistent API token is written to the output file. The temporary login token is automatically cleaned up.

## Requirements

- Ansible 2.10+
- Target Rancher server accessible via HTTPS
- Admin credentials (username/password)

## Quick Start

### Using the Playbook

```bash
# Basic usage with inventory
ansible-playbook -i inventory.yml ansible/rancher/token/generate-admin-token.yml

# With explicit URL via environment variable
RANCHER_URL=https://rancher.example.com \
  ansible-playbook ansible/rancher/token/generate-admin-token.yml

# With custom password via environment variable
RANCHER_URL=https://rancher.example.com \
RANCHER_ADMIN_PASSWORD=mypassword \
  ansible-playbook ansible/rancher/token/generate-admin-token.yml

# Override via extra vars
ansible-playbook ansible/rancher/token/generate-admin-token.yml \
  -e rancher_url=https://rancher.example.com \
  -e rancher_token_password=mypassword
```

### Using the Role Directly

```yaml
- hosts: localhost
  roles:
    - role: rancher_auth
      vars:
        rancher_url: "https://rancher.example.com"
        rancher_token_password: "{{ lookup('env', 'RANCHER_PASSWORD') }}"
```

## URL Resolution Priority

The Rancher URL is determined in the following order:

1. `RANCHER_URL` environment variable (when using the playbook)
2. `rancher_url` variable (explicit)
3. `external_lb_hostname` from inventory (prefixed with https://)
4. `internal_lb_hostname` from inventory (prefixed with https://)

## Role Variables

### Required Variables

One of the following must be available:

| Variable | Description | Example |
|----------|-------------|---------|
| `rancher_url` | Rancher server URL | `https://rancher.example.com` |
| `external_lb_hostname` | External hostname from inventory | `rancher.example.com` |
| `internal_lb_hostname` | Internal hostname from inventory | `rancher.internal` |

### Authentication Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `rancher_token_username` | `admin` | Username for authentication |
| `rancher_token_password` | `rancherrocks` | Password (falls back to `rancher_bootstrap_password`) |

Environment variables:
- `RANCHER_ADMIN_PASSWORD` - Sets `rancher_token_password` when using the playbook

### Token Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `rancher_token_ttl` | `0` | Token TTL in milliseconds (0 = no expiration) |

### Output Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `rancher_token_output_file` | `/tmp/rancher-admin-token` | Path to write the token |
| `rancher_token_output_format` | `token` | Output format: `token`, `json`, or `tfvars` |
| `rancher_cattle_config_file` | `""` | Path to cattle-config.yaml to update (optional) |

### Password Management

| Variable | Default | Description |
|----------|---------|-------------|
| `rancher_permanent_password` | `""` | If set (non-empty), sets this as the permanent password after first login |

Note: The permanent password is only set when `rancher_permanent_password` is defined and non-empty.
This replaces the previous `rancher_set_permanent_password` boolean flag.

### API Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `rancher_validate_certs` | `false` | Validate SSL certificates |

## Output Facts

After execution, the following facts are available:

| Fact | Description |
|------|-------------|
| `rancher_generated_token` | The generated API token |
| `rancher_generated_token_id` | Token ID in Rancher |
| `rancher_generated_token_name` | Token name in Rancher |

## Usage Examples

### Basic Usage - Generate Admin Token

```yaml
- hosts: localhost
  roles:
    - role: rancher_auth
      vars:
        rancher_url: "https://rancher.example.com"
        rancher_token_password: "{{ lookup('env', 'RANCHER_PASSWORD') }}"
```

### Token with Expiration

```yaml
- hosts: localhost
  roles:
    - role: rancher_auth
      vars:
        rancher_url: "https://rancher.example.com"
        rancher_token_password: "mypassword"
        rancher_token_ttl: 86400000  # 24 hours in milliseconds
```

### Update Cattle Config

```yaml
- hosts: localhost
  roles:
    - role: rancher_auth
      vars:
        rancher_url: "https://rancher.example.com"
        rancher_token_password: "mypassword"
        rancher_cattle_config_file: "/path/to/cattle-config.yaml"
```

### JSON Output for CI/CD

```yaml
- hosts: localhost
  roles:
    - role: rancher_auth
      vars:
        rancher_url: "https://rancher.example.com"
        rancher_token_password: "mypassword"
        rancher_token_output_format: "json"
        rancher_token_output_file: "/tmp/rancher-credentials.json"
```

### First Login with Permanent Password

```yaml
- hosts: localhost
  roles:
    - role: rancher_auth
      vars:
        rancher_url: "https://rancher.example.com"
        rancher_token_password: "bootstrap-password"
        rancher_permanent_password: "new-secure-password"
```

## Output Formats

### Plain Token (`token`)
```
token-abc123:secretvalue
```

### JSON (`json`)
```json
{
  "rancher_url": "https://rancher.example.com",
  "token": "token-abc123:secretvalue",
  "token_id": "token-abc123",
  "token_name": "token-abc123",
  "user_id": "user-abc123",
  "description": "automation-token",
  "ttl": 0,
  "created_at": "2025-01-23T10:00:00Z"
}
```

### Terraform Variables (`tfvars`)
```hcl
# Generated by rancher_auth role at 2025-01-23T10:00:00Z
fqdn = "https://rancher.example.com"
api_key = "token-abc123:secretvalue"
```

## Integration with Jenkins

```groovy
stage('Generate Admin Token') {
    sh """
        RANCHER_URL=https://${rancherHostname} \
        RANCHER_ADMIN_PASSWORD=${adminPassword} \
        ansible-playbook ansible/rancher/token/generate-admin-token.yml \
            -e rancher_cattle_config_file=${cattleConfigPath}
    """
}
```

## Integration with GitHub Actions

```yaml
- name: Generate Rancher Token
  env:
    RANCHER_URL: ${{ secrets.RANCHER_URL }}
    RANCHER_ADMIN_PASSWORD: ${{ secrets.RANCHER_PASSWORD }}
  run: |
    ansible-playbook ansible/rancher/token/generate-admin-token.yml \
      -e rancher_token_output_format=json \
      -e rancher_token_output_file=/tmp/rancher-token.json
```

## License

Apache-2.0

## Author

Rancher QA Team
