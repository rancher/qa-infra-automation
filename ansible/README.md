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