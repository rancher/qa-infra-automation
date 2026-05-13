# Prerequisites

Everything you need before deploying a cluster with this repository.

## Required Tools

| Tool | Version | Purpose | Install |
|------|---------|---------|---------|
| **Python** | 3.11+ | Runs Ansible and helper scripts | [python.org](https://www.python.org/downloads/) |
| **Ansible** | core 2.16+ | Deploys K8s and Rancher onto nodes | Installed via `requirements.txt` |
| **OpenTofu** | 1.6+ | Provisions cloud infrastructure | [opentofu.org](https://opentofu.org/docs/intro/install/) |
| **kubectl** | any recent | Verifies the cluster after deployment | [kubernetes.io](https://kubernetes.io/docs/tasks/tools/) |
| **Helm** | 3.x | Required only for Rancher deployment | [helm.sh](https://helm.sh/docs/intro/install/) |

> **Note:** OpenTofu is only needed if you're provisioning infrastructure through this repo. If you're bringing your own nodes, you can skip it.

## Install Python Dependencies

From the repository root:

```bash
# Create and activate a virtualenv (recommended)
python3 -m venv .venv
source .venv/bin/activate

# Install Python packages (ansible-core, kubernetes client, jmespath, boto3, ...)
pip install -r requirements.txt

# Install Ansible collections (kubernetes.core, community.general, cloud.terraform, ...)
ansible-galaxy collection install -r requirements.yml
```

<details>
<summary>Alternative: using pipx</summary>

If you manage Ansible with `pipx` instead of a venv, inject the dependencies into the same environment:

```bash
pipx install ansible
pipx inject ansible -r requirements.txt
ansible-galaxy collection install -r requirements.yml
```

</details>

## Verify Everything Is Installed

The Makefile includes a one-command check:

```bash
make validate
```

This confirms `tofu`, `ansible`, and `ansible-playbook` are available, Python dependencies are importable, and Ansible collections are present.

## Cloud Provider Credentials

You only need credentials for the provider you plan to use. Skip this section entirely if you're bringing your own nodes.

### AWS

Set these environment variables or put them in `terraform.tfvars`:

```bash
export AWS_ACCESS_KEY_ID="your-access-key"
export AWS_SECRET_ACCESS_KEY="your-secret-key"
```

You also need an existing **VPC**, **Subnet**, and **Security Group** in your target region. These are passed as variables to the Tofu module.

### GCP

Configure a service account and set:

```bash
export GOOGLE_APPLICATION_CREDENTIALS="/path/to/service-account.json"
```

### Other Providers

See [Adding a New Provider](adding-a-provider.md) for the provider contract.

## SSH Key Pair

All deployments require an SSH key pair for Ansible to connect to nodes:

```bash
# Generate one if you don't have one
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519 -N ""
```

- The **public key** is injected into VMs during provisioning (or must be pre-installed on BYO nodes).
- The **private key** is used by Ansible for SSH connections.

## Next Steps

You're ready to deploy. Pick a guide:

- [RKE2 on AWS](guides/rke2-default-aws.md)
- [RKE2 on your own nodes](guides/rke2-default-byo.md)
- [K3s on AWS](guides/k3s-default-aws.md)
- [K3s on your own nodes](guides/k3s-default-byo.md)
- [RKE2 airgap on AWS](guides/rke2-airgap-aws.md)
- [All guides](guides/README.md)
