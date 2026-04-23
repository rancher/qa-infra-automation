# Deploy RKE2 on AWS (Default / Internet-Connected)

> **Estimated time:** ~15 minutes
>
> **What you'll end up with:** A multi-node RKE2 Kubernetes cluster running on AWS EC2 instances with Calico CNI, a kubeconfig on your local machine, and optionally Rancher installed on top.

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

# Region and networking — fill these in from your AWS account
aws_region          = "us-east-2"
aws_vpc             = "vpc-xxxxxxxx"
aws_subnet          = "subnet-xxxxxxxx"
aws_security_group  = ["sg-xxxxxxxx"]

# DNS (optional — creates a Route53 record for the cluster FQDN)
aws_route53_zone    = "qa.rancher.space"

# Instance settings
aws_ami             = "ami-01de4781572fa1285"   # SLES 15 SP7 in us-east-2
aws_ssh_user        = "ec2-user"                # Default SSH user for the AMI
instance_type       = "t3a.medium"              # 2 vCPU, 4 GB RAM
aws_volume_size     = 40
aws_volume_type     = "gp3"
aws_hostname_prefix = "yourname"                # Prefix for EC2 Name tags

# SSH key — path to the public key to inject into instances
public_ssh_key      = "~/.ssh/id_ed25519.pub"

# Cluster topology
nodes = [
  {
    count = 3
    role  = ["etcd", "cp", "worker"]   # 3 all-in-one nodes
  }
]

# Standard (non-airgap) deployment
airgap_setup = false
proxy_setup  = false
```

> **Tip:** For a minimal test cluster, `count = 1` with all three roles works fine. For production-like setups, separate etcd, cp, and worker roles across node groups.

## Step 2: Provision Infrastructure

From the repository root:

```bash
make infra-up
```

This runs `tofu apply`, creates the EC2 instances, and auto-generates the Ansible inventory at `ansible/rke2/default/inventory/inventory.yml`.

<details>
<summary>Manual alternative (without Make)</summary>

```bash
tofu -chdir=tofu/aws/modules/cluster_nodes init
tofu -chdir=tofu/aws/modules/cluster_nodes apply -var-file=terraform.tfvars -auto-approve

# Generate inventory
tofu -chdir=tofu/aws/modules/cluster_nodes output -raw cluster_nodes_json > /tmp/nodes.json
python3 scripts/generate_inventory.py \
  --input /tmp/nodes.json \
  --distro rke2 --env default \
  --schema ansible/_inventory-schema.yaml \
  --output-dir ansible/rke2/default/inventory
```

</details>

Verify the inventory looks correct:

```bash
ansible-inventory -i ansible/rke2/default/inventory/inventory.yml --list
```

## Step 3: Configure the Cluster

Create the file `ansible/rke2/default/vars.yaml`:

```yaml
# RKE2 version — find versions at https://github.com/rancher/rke2/releases
kubernetes_version: 'v1.34.2+rke2r1'

# CNI plugin (calico, canal, or cilium)
cni: "calico"

# Kubeconfig output location
kubeconfig_file: './kubeconfig.yaml'
```

> **Note:** `fqdn` and `kube_api_host` are automatically populated from the Tofu-generated inventory. You don't need to set them here.

## Step 4: Deploy the Cluster

```bash
make cluster
```

This runs the RKE2 Ansible playbook which:
1. Installs OS packages on all nodes
2. Generates RKE2 config files
3. Downloads and installs RKE2 binaries
4. Starts the master node, distributes the join token, starts remaining nodes
5. Runs health checks and downloads the kubeconfig locally

<details>
<summary>Manual alternative (without Make)</summary>

```bash
ansible-playbook \
  -i ansible/rke2/default/inventory/inventory.yml \
  ansible/rke2/default/rke2-playbook.yml
```

</details>

## Step 5: Verify the Cluster

```bash
kubectl --kubeconfig ansible/rke2/default/kubeconfig.yaml get nodes -o wide
```

Expected output (3 nodes, all `Ready`):

```
NAME     STATUS   ROLES                       AGE   VERSION            INTERNAL-IP
master   Ready    control-plane,etcd,master   5m    v1.34.2+rke2r1    10.0.1.10
cp-0     Ready    control-plane,etcd,master   4m    v1.34.2+rke2r1    10.0.1.11
cp-1     Ready    control-plane,etcd,master   3m    v1.34.2+rke2r1    10.0.1.12
```

Check all system pods are running:

```bash
kubectl --kubeconfig ansible/rke2/default/kubeconfig.yaml get pods -A
```

## Step 6: (Optional) Deploy Rancher

See the [Rancher HA guide](rancher-ha.md) for full instructions. The quick version:

```bash
make rancher
```

## Step 7: Cleanup

Destroy all AWS resources when you're done:

```bash
make infra-down
```

Or to skip the confirmation prompt:

```bash
cd tofu/aws/modules/cluster_nodes && tofu destroy -var-file=terraform.tfvars -auto-approve
```

## Troubleshooting

**`make infra-up` fails with credential errors**
- Verify your `aws_access_key` and `aws_secret_key` in `terraform.tfvars`
- Alternatively, set `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` environment variables

**Ansible can't SSH to nodes**
- Ensure your `public_ssh_key` path is correct and the key was injected during provisioning
- Check that the security group allows SSH (port 22) from your IP
- Test connectivity: `make ping`

**RKE2 service fails to start**
- SSH into the node and check logs: `journalctl -u rke2-server --no-pager -n 50`
- Verify the security group allows ports 6443, 9345, and 10250 between nodes

**Health checks fail (nodes not Ready)**
- Wait a few minutes — nodes may still be joining
- Re-run just the health check: `ansible-playbook -i ansible/rke2/default/inventory/inventory.yml ansible/rke2/default/rke2-playbook.yml --tags health`

For more, see [Troubleshooting](../reference/troubleshooting.md).

## Next Steps

- [Deploy Rancher](rancher-ha.md) on top of your cluster
- [Run specific playbook phases](../../ansible/rke2/default/README.md) using Ansible tags
- [Add more worker nodes](../../tofu/aws/modules/cluster_nodes/README.md) by updating the `nodes` variable and re-running `make infra-up` + `make cluster`
