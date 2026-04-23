# Deploy RKE2 in Airgap on AWS

> **Estimated time:** ~25 minutes
>
> **What you'll end up with:** An RKE2 cluster running in an air-gapped (no internet) private network on AWS, accessed through a bastion host. Optionally with Rancher deployed on top.

This is the most complex deployment path. Nodes have no internet access — RKE2 is installed via pre-downloaded tarballs transferred through a bastion host.

## Prerequisites

- Complete the [general prerequisites](../prerequisites.md) (Python, Ansible, OpenTofu, SSH key)
- AWS credentials with permissions to create VPCs, subnets, NAT gateways, and EC2 instances
- Familiarity with [RKE2 on AWS (default)](rke2-default-aws.md) is recommended — try that first

## Architecture Overview

```
┌──────────────────────────────────────────────────────────┐
│  AWS VPC                                                  │
│                                                           │
│  ┌─────────────┐      ┌──────────────────────────────┐   │
│  │  Public      │      │  Private Subnet (no internet) │   │
│  │  Subnet      │      │                                │   │
│  │  ┌─────────┐ │  SSH │  ┌─────────┐  ┌─────────┐    │   │
│  │  │ Bastion │─┼──────┼─▶│ RKE2    │  │ RKE2    │    │   │
│  │  │         │ │      │  │ Server  │  │ Server  │    │   │
│  │  └─────────┘ │      │  └─────────┘  └─────────┘    │   │
│  └─────────────┘      └──────────────────────────────┘   │
└──────────────────────────────────────────────────────────┘
     ▲ You SSH here
```

- **Bastion host**: Has internet access. Downloads RKE2 tarballs and transfers them to airgap nodes.
- **Airgap nodes**: No internet. Run RKE2 from the tarballs.
- **All Ansible commands** proxy through the bastion via SSH.

## Step 1: Configure Infrastructure

Create the file `tofu/aws/modules/airgap/terraform.tfvars`:

```hcl
# AWS credentials
aws_access_key      = "AKIA..."
aws_secret_key      = "your-secret-key"

# Region
aws_region          = "us-east-2"

# Instance settings
aws_ami             = "ami-01de4781572fa1285"   # SLES 15 SP7 in us-east-2
aws_ssh_user        = "ec2-user"
instance_type       = "t3a.xlarge"
aws_hostname_prefix = "yourname"

# SSH key
public_ssh_key      = "~/.ssh/id_ed25519.pub"
```

> The airgap module creates its own VPC, subnets, bastion host, and security groups automatically — you don't need to provide them.

## Step 2: Provision Infrastructure

```bash
make infra-up ENV=airgap
```

This creates:
- A VPC with public and private subnets
- A bastion host in the public subnet
- RKE2 nodes in the private subnet (no internet)
- An auto-generated Ansible inventory at `ansible/rke2/airgap/inventory/inventory.yml`

## Step 3: Configure the Cluster

The Tofu module generates an inventory and group vars template. Review and customize:

```bash
# Review the generated inventory
cat ansible/rke2/airgap/inventory/inventory.yml

# Review/edit group vars
cp ansible/rke2/airgap/inventory/group_vars/all.yml.template \
   ansible/rke2/airgap/inventory/group_vars/all.yml
```

Key settings in `group_vars/all.yml`:

```yaml
# RKE2 version (optional — defaults to latest stable)
# rke2_version: "v1.34.2+rke2r1"

# SSH key for bastion proxy
ssh_private_key_file: "~/.ssh/id_ed25519"

# CNI plugin (canal is the default for airgap)
cni: "canal"

# Network configuration
cluster_cidr: "10.42.0.0/16"
service_cidr: "10.43.0.0/16"
cluster_dns: "10.43.0.10"
```

See the [Group Vars Guide](../../ansible/rke2/airgap/docs/configuration/GROUP_VARS_GUIDE.md) for all options.

## Step 4: Deploy the Cluster

```bash
make cluster ENV=airgap
```

This runs the tarball playbook which:
1. Downloads RKE2 tarballs on the bastion host
2. Transfers tarballs to airgap nodes through SSH
3. Installs RKE2 from the tarballs (no internet required on nodes)
4. Forms the cluster (server first, then agents)
5. Sets up kubectl access on the bastion

<details>
<summary>Manual alternative</summary>

```bash
ansible-playbook \
  -i ansible/rke2/airgap/inventory/inventory.yml \
  ansible/rke2/airgap/playbooks/deploy/rke2-tarball-playbook.yml
```

</details>

## Step 5: Verify

SSH to the bastion and check the cluster:

```bash
make ssh-bastion ENV=airgap
# On the bastion:
kubectl get nodes -o wide
kubectl get pods -A
```

Or test connectivity from your workstation through the bastion:

```bash
make status ENV=airgap
```

## Step 6: (Optional) Configure Private Registry

If you need to pull additional container images after installation:

```bash
make registry ENV=airgap
```

This configures `/etc/rancher/rke2/registries.yaml` on all airgap nodes. See the [airgap README](../../ansible/rke2/airgap/README.md#private-registry-configuration) for registry configuration details.

## Step 7: (Optional) Deploy Rancher

```bash
make rancher ENV=airgap
```

This deploys Rancher via Helm on the bastion host. See the [airgap README](../../ansible/rke2/airgap/README.md#6-deploy-rancher-optional) for Rancher configuration variables and post-deployment steps.

## Step 8: Cleanup

```bash
make infra-down ENV=airgap
```

## Troubleshooting

**Can't SSH to bastion**
- Check that the bastion's security group allows SSH (port 22) from your IP
- Verify `ssh_private_key_file` matches the key used during provisioning

**Ansible can't reach airgap nodes**
- All airgap traffic goes through the bastion via SSH proxy
- Test connectivity: `make test-ssh ENV=airgap`
- See [SSH Troubleshooting](../../ansible/rke2/airgap/docs/knowledge_base/SSH_TROUBLESHOOTING.md)

**Tarball download fails on bastion**
- Ensure the bastion has internet access (it should be in the public subnet)
- Check disk space: tarballs need ~5 GB on the bastion

**RKE2 fails to start on airgap nodes**
- Verify tarballs transferred correctly: check file sizes on the airgap nodes
- Check logs: `journalctl -u rke2-server --no-pager -n 50`
- Run the checksum fix: `ansible-playbook -i ansible/rke2/airgap/inventory/inventory.yml ansible/rke2/airgap/playbooks/debug/fix-checksum-issues.yml`

For more, see the [airgap troubleshooting section](../../ansible/rke2/airgap/README.md#troubleshooting) and [Troubleshooting](../reference/troubleshooting.md).

## Next Steps

- [Import a downstream cluster](../../docs/import_cluster_on_airgap.md) into an airgapped Rancher
- [Upgrade RKE2](../../ansible/rke2/airgap/docs/configuration/RKE2_UPGRADE_GUIDE.md) in an airgap environment
- [CNI configuration options](../../ansible/rke2/airgap/docs/configuration/CNI_CONFIGURATION_GUIDE.md)
- [Full airgap reference](../../ansible/rke2/airgap/README.md)
