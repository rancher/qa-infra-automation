# Deploy K3s on AWS (Default / Internet-Connected)

> **Estimated time:** ~10 minutes
>
> **What you'll end up with:** A multi-node K3s Kubernetes cluster running on AWS EC2 instances, a kubeconfig on your local machine, and optionally Rancher installed on top.

K3s is a lightweight Kubernetes distribution ideal for edge computing, development, and CI environments. If you need a heavier, security-focused distribution, see the [RKE2 on AWS guide](rke2-default-aws.md) instead.

## Prerequisites

- Complete the [general prerequisites](../prerequisites.md) (Python, Ansible, OpenTofu, SSH key)
- AWS credentials configured (access key + secret key)
- An existing AWS **VPC**, **Subnet**, and **Security Group** in your target region

## Step 1: Configure Infrastructure

Create the file `tofu/aws/modules/cluster_nodes/terraform.tfvars`:

```hcl
# AWS credentials
aws_access_key      = "AKIA..."
aws_secret_key      = "your-secret-key"

# Region and networking
aws_region          = "us-east-2"
aws_vpc             = "vpc-xxxxxxxx"
aws_subnet          = "subnet-xxxxxxxx"
aws_security_group  = ["sg-xxxxxxxx"]

# DNS (optional)
aws_route53_zone    = "qa.rancher.space"

# Instance settings
aws_ami             = "ami-01de4781572fa1285"   # SLES 15 SP7 in us-east-2
aws_ssh_user        = "ec2-user"
instance_type       = "t3a.medium"
aws_volume_size     = 40
aws_volume_type     = "gp3"
aws_hostname_prefix = "yourname"

# SSH key
public_ssh_key      = "~/.ssh/id_ed25519.pub"

# Cluster topology — K3s uses cp and worker roles (not etcd separately)
nodes = [
  {
    count = 3
    role  = ["etcd", "cp", "worker"]
  }
]

airgap_setup = false
proxy_setup  = false
```

> **Note:** K3s uses the same Tofu module as RKE2 — the infrastructure is identical. The difference is in the Ansible layer.

## Step 2: Provision Infrastructure

```bash
make infra-up DISTRO=k3s
```

This creates EC2 instances and generates the inventory at `ansible/k3s/default/inventory/inventory.yml`.

Verify the inventory:

```bash
ansible-inventory -i ansible/k3s/default/inventory/inventory.yml --list
```

## Step 3: Configure the Cluster

Create the file `ansible/k3s/default/vars.yaml`:

```yaml
# K3s version — find versions at https://github.com/k3s-io/k3s/releases
kubernetes_version: 'v1.35.2+k3s1'

# Kubeconfig output location
kubeconfig_file: './kubeconfig.yaml'

# Optional: K3s release channel (stable, latest, testing)
channel: "stable"
```

## Step 4: Deploy the Cluster

```bash
make cluster DISTRO=k3s
```

<details>
<summary>Manual alternative</summary>

```bash
ansible-playbook \
  -i ansible/k3s/default/inventory/inventory.yml \
  ansible/k3s/default/k3s-playbook.yml
```

</details>

## Step 5: Verify

```bash
kubectl --kubeconfig ansible/k3s/default/kubeconfig.yaml get nodes -o wide
```

All nodes should show `Ready`. Check system pods:

```bash
kubectl --kubeconfig ansible/k3s/default/kubeconfig.yaml get pods -A
```

## Step 6: (Optional) Deploy Rancher

See the [Rancher HA guide](rancher-ha.md).

```bash
make rancher DISTRO=k3s
```

## Step 7: Cleanup

```bash
make infra-down DISTRO=k3s
```

## Troubleshooting

**K3s service fails to start**
- SSH in and check: `journalctl -u k3s --no-pager -n 50`
- Ensure ports 6443 and 10250 are open between nodes

**Nodes not joining the cluster**
- Verify the join token was distributed: check Ansible output for the "distribute token" task
- Ensure all nodes can reach the master on port 6443

For more, see [Troubleshooting](../reference/troubleshooting.md).

## Next Steps

- [Deploy Rancher](rancher-ha.md) on top of your cluster
- [K3s playbook details](../../ansible/k3s/default/README.md) for advanced configuration
