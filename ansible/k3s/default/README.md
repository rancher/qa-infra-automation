# K3s Cluster Ansible Playbook

This playbook deploys a K3s Kubernetes cluster using Ansible roles for improved maintainability.

## Prerequisites

Before running the playbook, ensure you have the following in addition to the [general ansible prereqs](../../README.md):

- SSH access to the target nodes
- A valid inventory file (see inventory options below)
- A `vars.yaml` file with necessary variables

## Inventory Options

Choose one of the following inventory approaches:

### Option 1: Terraform/OpenTofu

For infrastructure managed by Terraform/OpenTofu:

```bash
# Set required environment variables
export TF_WORKSPACE="your-workspace"
export TERRAFORM_NODE_SOURCE="tofu/aws/modules/cluster_nodes"

# Use the Terraform inventory
ansible-playbook -i inventory-template.yml k3s-playbook.yml --extra-vars "@vars.yaml"
```

### Option 2: Generic Inventory

For "manually" managed infrastructure:

```bash
# Set required environment variables
export MASTER_IP="192.168.1.10"
export MASTER_ROLE="etcd,cp,worker"
export SERVER1_IP="192.168.1.11"            # Optional
export SERVER1_ROLE="etcd,cp,worker"        # Optional
export WORKER1_IP="192.168.1.20"            # Optional
export WORKER1_ROLE="worker"                # Optional
export ANSIBLE_USER="ubuntu"
export ANSIBLE_SSH_KEY="~/.ssh/id_rsa"

# Generate inventory from template
envsubst < inventory-template.yml > my-inventory.yml

# Use the generic inventory
ansible-playbook -i my-inventory.yml k3s-playbook.yml --extra-vars "@vars.yaml"
```

## Usage

### Configuration permissions

The install role makes `/etc/rancher/k3s` traversable and keeps regular
configuration files, including hidden files and pre-existing backups, at `0600`.
Rendering `config.yaml` does not create new backups (`backup: false`), avoiding
additional copies of configuration secrets. Only the
admin kubeconfig `/etc/rancher/k3s/k3s.yaml` remains readable at `0644`; use these
QA hosts only with trusted local users. Configuration symlinks stop the role
with the K3s directory private until the links are replaced with regular files.
If `/etc/rancher` or `/etc/rancher/k3s` itself is a symlink, including a broken link, the role
stops before changing any files or permissions. The link and its target remain
untouched; replace the link with a real configuration directory before rerunning.

For fresh hosts and legacy `/etc/rancher` parents at `0700`, the role adds only
directory traversal, preserving existing read/write permissions. If a private
parent contains anything besides `k3s`, it fails without opening the parent or
modifying those sibling entries. Secure those entries and explicitly grant
parent traversal before rerunning; do not recursively relax permissions.

### Basic Deployment

```bash
# Set ANSIBLE_CONFIG (optional)
export ANSIBLE_CONFIG=/path/to/qa-infra-automation/ansible/k3s/default/ansible.cfg

# Run with Terraform inventory
ansible-playbook -i inventory-template.yml k3s-playbook.yml --extra-vars "@vars.yaml" -vvv

# Or run with generic inventory
ansible-playbook -i my-inventory.yml k3s-playbook.yml --extra-vars "@vars.yaml"  -vvv
```

### Configuration Setup

Before running the playbook, create your `vars.yaml` file:

```bash
# Copy the example template
cp vars.yaml.example vars.yaml

# Edit with your specific values
vim vars.yaml
```

**Sample `vars.yaml`:**

```yaml
# K3s version and installation
kubernetes_version: 'v1.33.1+k3s1'
kubeconfig_file: './kubeconfig.yaml'
```

### Registry Support

If you would like to use a mirror or registry, upload a file to `roles/k3s_install/tasks/` named `k3s_registy.yaml`

### Commit builds

Commit installs require `jq`, `unzip` and a GitHub token with permission to read
Actions artifacts in `k3s-io/k3s`. Store the token in Jenkins Credentials and bind
it as `GITHUB_TOKEN` for the job. If Ansible runs inside a container, pass that
environment variable into the container too. Do not put the token in inventory,
`vars.yaml` or command-line arguments.

The role reads the controller environment through `k3s_github_token` and passes
the token to the remote installer through stdin with `no_log: true`. A missing
token stops the commit-install block before its prerequisites are installed.
Surrounding whitespace is trimmed once for both transport and diagnostics;
tokens with internal CR/LF characters are rejected before installation.
Version-tag installs do not require the token.

After the install retries are exhausted, the role fails with the exit code
and the last 2000 characters of the module message and each output stream. It replaces
the literal token before truncating or displaying stdout and stderr.
Module errors without an exit code retain their sanitized message.

The role installs both tools before downloading the installer. On transactional
hosts such as SLE Micro, it reboots if the tools are still missing from the running
system, then waits for both tools and the SSH user's home before continuing.
Package installation retries up to 20 times at 30-second intervals on transactional
hosts, or 3 times at 20-second intervals elsewhere. Zypper's missing-package
exit 104 is handled immediately instead of repeating a deterministic failure.

On nontransactional SUSE hosts, if zypper cannot find `jq` (exit 104), the role
downloads jq 1.8.2 from the official jqlang release through `download_verify`.
AMD64 and ARM64 assets have pinned SHA256 digests. Other package errors still
stop installation; `unzip` and transactional hosts keep the package path.
The fallback lives in a private temporary directory under `/usr/local/bin`
(`k3s_install_tools_parent`), so it works when `/tmp` is mounted `noexec`.
Only the installer gets that directory in its PATH; the role removes it on
success or failure. The host must be able to download GitHub release assets.
