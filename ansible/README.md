# Ansible

## Prerequisites

Before running a playbook, ensure you have the following:

*   **Python 3.12+**
*   **Ansible-core 2.21.1** (pinned via `requirements.txt`)
*   **Tofu (Optional):** If you're using the provided inventory, you'll need OpenTofu installed and configured to manage your infrastructure.

## Installation

From the repository root:

```bash
# 1. Create and activate a virtualenv (recommended)
python3 -m venv .venv
source .venv/bin/activate

# 2. Install Python dependencies (ansible-core, kubernetes client, jmespath, boto3, ...)
pip install -r requirements.txt

# 3. Install Ansible collections
ansible-galaxy collection install -r requirements.yml
```

If you manage Ansible with `pipx` instead of a venv, install `ansible-core`
with the same pin, then inject the extra deps into that environment so the
Python modules are importable at runtime:

```bash
pipx install "ansible-core==2.21.1"   # if not already installed
pipx inject ansible-core pyyaml jmespath kubernetes boto3 botocore
ansible-galaxy collection install -r requirements.yml
```

Many tasks run on `localhost` (the control node) against the remote cluster,
so these Python libraries must be present in the interpreter that runs
`ansible-playbook`, not on the managed hosts.

## Building for GO

Package ansible provides embedded Ansible playbooks, roles, and configuration
files from the qa-infra-automation repository.

Usage:

`import "github.com/rancher/qa-infra-automation/ansible"`

Files is an embed.FS containing all Ansible content.
Paths are relative, e.g. "roles/k3s_install/tasks/main.yml",
"rke2/default/rke2-playbook.yml", etc.

`fs.WalkDir(ansible.Files, ".", func(path string, d fs.DirEntry, err error) error { ... })`

