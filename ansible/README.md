# Ansible

## Prerequisites

Before running a playbook, ensure you have the following:

*   **Ansible:** Version 2.9 or later is recommended.
*   **Python 3.11+**  Along with the `ansible` and `kubernetes` packages.
*   **Tofu (Optional):** If you're using the provided inventory, you'll need OpenTofu installed and configured to manage your infrastructure.

## Installation

1.  **Install Ansible and its dependencies:**
    ```bash
    ansible-galaxy collection install cloud.terraform
    ```


2.  **Install required Python packages:**

    ```bash
    python3 -m pip install ansible kubernetes
    ```

    **Note:** you may need to add the flag `--break-system-packages` if not using a venv

## Ansible Configuration

A shared `ansible.cfg` lives at `ansible/ansible.cfg` and applies to all playbooks in this directory tree. It sets common defaults for timeouts, SSH multiplexing, fact caching, and the central roles path.

### Running playbooks locally

If you run `ansible-playbook` from within the `ansible/` directory, the shared config is picked up automatically:

```bash
cd ansible/
ansible-playbook k3s/default/k3s-playbook.yml -i <inventory>
```

> **Note:** If a product subdirectory contains its own `ansible.cfg` (e.g. `rke2/airgap/ansible.cfg`), that local config takes precedence over the shared one when your working directory is inside that subdirectory. See [Product-specific overrides](#product-specific-overrides) below.

If you run from the repo root or another directory, point Ansible to the shared config explicitly:

```bash
ANSIBLE_CONFIG=ansible/ansible.cfg ansible-playbook ansible/k3s/default/k3s-playbook.yml -i <inventory>
```

### Running playbooks in CI/Jenkins

Set `ANSIBLE_CONFIG` in your pipeline before invoking any playbook:

```groovy
env.ANSIBLE_CONFIG = "${WORKSPACE}/ansible/ansible.cfg"
```

or in a shell step:

```bash
export ANSIBLE_CONFIG="${WORKSPACE}/ansible/ansible.cfg"
ansible-playbook ansible/k3s/default/k3s-playbook.yml -i <inventory>
```

### Product-specific overrides

Two products have settings that cannot be shared globally and keep their own configs:

| File | Purpose |
|---|---|
| `rke2/airgap/ansible.cfg` | Sets `inventory`, `remote_user`, and `stdout_callback` for airgap deployments |
| `chaos/ansible.cfg` | Sets `localhost_warning` and `inventory_ignore_patterns` for chaos experiments |

When running those playbooks, set `ANSIBLE_CONFIG` to the product-specific file instead:

```bash
ANSIBLE_CONFIG=ansible/rke2/airgap/ansible.cfg ansible-playbook ...
```

> **Important:** Ansible does not merge config files. When `ANSIBLE_CONFIG` points to a product-specific `ansible.cfg`, settings from the shared `ansible/ansible.cfg` (including `roles_path`) are **not** inherited. To ensure roles are still resolved from `ansible/roles/`, set `ANSIBLE_ROLES_PATH` explicitly:
>
> ```bash
> export ANSIBLE_ROLES_PATH=$(pwd)/ansible/roles
> ANSIBLE_CONFIG=ansible/rke2/airgap/ansible.cfg ansible-playbook ...
> ```
>
> The `Makefile` handles this automatically — it sets both `ANSIBLE_CONFIG` and `ANSIBLE_ROLES_PATH` for all targets.

### Roles

All reusable roles live in `ansible/roles/`. The shared `ansible.cfg` sets `roles_path = ./roles`, which resolves correctly when the working directory is `ansible/` and the shared config is in use. Product-specific configs intentionally omit `roles_path` — use `ANSIBLE_ROLES_PATH` instead so that the central roles directory is always authoritative.