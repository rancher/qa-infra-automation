# Rancher User Setup Role

Create Rancher local users with global and project role bindings for CI/CD
test pipelines.

## Features

- **User Creation**: Create local Rancher users via the `/v3/users` API
- **Global Role Bindings**: Assign global roles (e.g. `user`, `admin`, `restricted-admin`)
- **Project Role Bindings**: Assign project-scoped roles (e.g. `project-member`, `project-owner`)
- **Login Verification**: Optionally verify each user can log in after creation
- **Idempotent**: Gracefully handles existing users (409/422 status codes)
- **Configurable Error Handling**: Fail or warn when verification fails

## How It Works

1. **Login** — Authenticates as admin to get a bearer token
2. **Create users** — Loops over `rancher_users` list, creating each user
3. **Bind roles** — Assigns global and project role bindings per user
4. **Verify** — Optionally logs in as each user to confirm access

## Requirements

- Ansible 2.10+
- Target Rancher server accessible via HTTPS
- Admin credentials (username/password)

## Quick Start

```yaml
- hosts: localhost
  connection: local
  roles:
    - role: rancher_user_setup
      vars:
        rancher_host: rancher.example.com
        rancher_admin_password: "{{ lookup('env', 'RANCHER_PASSWORD') }}"
        rancher_users:
          - username: standard_user
            password: "{{ lookup('env', 'RANCHER_PASSWORD') }}"
            global_roles: [user]
            project_roles:
              - role: project-member
```

## Role Variables

### Required

| Variable | Description | Example |
|----------|-------------|---------|
| `rancher_host` | Rancher server FQDN (no `https://` prefix) | `rancher.example.com` |
| `rancher_admin_password` | Admin password for API authentication | `password1234` |
| `rancher_users` | List of users to create (see format below) | — |

### Optional

| Variable | Default | Description |
|----------|---------|-------------|
| `rancher_validate_certs` | `false` | Validate TLS certificates |
| `rancher_user_on_error` | `warn` | Error handling: `fail` or `warn` |

### User List Format

Each entry in `rancher_users`:

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `username` | yes | — | Login name |
| `password` | yes | — | User password |
| `enabled` | no | `true` | Whether the user is enabled |
| `global_roles` | no | `[]` | List of global role IDs |
| `project_roles` | no | `[]` | List of project role binding dicts |
| `verify_login` | no | `true` | Verify the user can log in |

Each entry in `project_roles`:

| Field | Required | Default | Description |
|-------|----------|---------|-------------|
| `role` | yes | — | Role template ID (e.g. `project-member`) |
| `project` | no | `Default` | Project name |
| `cluster` | no | `local` | Cluster ID |

## Usage Examples

### Single User (Dashboard E2E)

```yaml
- hosts: localhost
  connection: local
  roles:
    - role: rancher_user_setup
      vars:
        rancher_host: "{{ rancher_fqdn }}"
        rancher_admin_password: "{{ rancher_password }}"
        # Fail fast if tests need standard_user but login failed; warn-only otherwise
        rancher_user_on_error: "{{ 'fail' if '@standardUser' in cypress_tags else 'warn' }}"
        rancher_users:
          - username: standard_user
            password: "{{ rancher_password }}"
            global_roles: [user]
            project_roles:
              - role: project-member
                project: Default
                cluster: local
```

### Multiple Users

```yaml
- hosts: localhost
  connection: local
  roles:
    - role: rancher_user_setup
      vars:
        rancher_host: "{{ rancher_fqdn }}"
        rancher_admin_password: "{{ rancher_password }}"
        rancher_users:
          - username: standard_user
            password: "{{ rancher_password }}"
            global_roles: [user]
            project_roles:
              - role: project-member
          - username: restricted_admin
            password: "{{ rancher_password }}"
            global_roles: [restricted-admin]
          - username: readonly_user
            password: "{{ rancher_password }}"
            global_roles: [user]
            project_roles:
              - role: read-only
                project: Default
```

### Strict Mode (Fail on Error)

```yaml
- role: rancher_user_setup
  vars:
    rancher_host: "{{ rancher_fqdn }}"
    rancher_admin_password: "{{ rancher_password }}"
    rancher_user_on_error: fail
    rancher_users:
      - username: test_user
        password: secure123
        global_roles: [user]
```

## Output Facts

After execution, the following facts are set per user (last user wins):

| Fact | Description |
|------|-------------|
| `_current_user_id` | Rancher user ID of the last created user |

For multi-user workflows that need individual IDs, query the Rancher API
after role execution.
