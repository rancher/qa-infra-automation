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

## Building for GO

Package ansible provides embedded Ansible playbooks, roles, and configuration
files from the qa-infra-automation repository.

Usage:

`import "github.com/rancher/qa-infra-automation/ansible"`

Files is an embed.FS containing all Ansible content.
Paths are relative, e.g. "roles/k3s_install/tasks/main.yml",
"rke2/default/rke2-playbook.yml", etc.

`fs.WalkDir(ansible.Files, ".", func(path string, d fs.DirEntry, err error) error { ... })`

