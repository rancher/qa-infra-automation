# Add downstream cluster to airgap Rancher guide

This guide provides step-by-step instructions for provisioning airgapped nodes and use them as a rancher cluster and a downstream cluster.

## Overview

The RKE2 upgrade process for airgap environments involves:
1. **Provision nodes** - Provision airgapped nodes, load balancers and bastion.
2. **Install RKE2 on both clusters** - Fetch RKE2 tarball bundle on bastion host.
3. **Install Rancher** - Install Rancher on the appropriate cluster. Here we use the tarball installation method for simplicity.
4. **Add cluster as downstream to Rancher** - Upgrade worker nodes one by one

## Process

### 1. Provision nodes

Run `tofu apply -var-file="terraform.tfvars"` with the desired `*.tfvars` file. This content can be used as a template:

```
aws_access_key        = "<your_access_key>"
aws_secret_key        = "<your_secret_key>"
aws_ami               = "<your_ami>"
instance_type         = "t3.xlarge"
aws_security_group    = ["<your_security_group>"]
aws_subnet            = "<your_subnet>"
aws_volume_size       = 100
aws_hostname_prefix   = "add-downstream-test"
aws_region            = "us-east-2"
aws_route53_zone      = "qa.rancher.space"
aws_ssh_user          = "root"
aws_vpc               = "<your_vpc>"
user_id               = "<your_user_id>"
ssh_key               = "<your_ssh_key>"
ssh_key_name          = "<your_ssh_key_name>"
provision_registry    = false # Not needed since we are going for the tarball installation method.
node_groups           = {
    rancher = 3 # The nodes dedicated to rancher should be keyed using "rancher" here.
    downstream = 3
}
```

This will generate an `inventory.yml` file on `qa-infra-automation/ansible/rke2/airgap/inventory/inventory.yml` that can be used with Ansible.

### 2. Install RKE2 on both clusters

From here on out, all the commands are being run from `qa-infra-automation/ansible/rke2/airgap`
First it is needed to set up SSH access on all the nodes so we can safely access the airgapped nodes using Ansible going through the bastion:

```bash
ansible-playbook -i inventory/inventory.yml playbooks/setup/setup-ssh-keys.yml
```

Then we install RKE2 in both groups of nodes:

```bash
ansible-playbook -i inventory/inventory.yml playbooks/deploy/rke2-tarball-playbook.yml # Group "rancher" is the default target group.
ansible-playbook -i inventory/inventory.yml playbooks/deploy/rke2-tarball-playbook.yml --extra-vars="target=airgap_nodes:downstream" # Install RKE2 on the downstream cluster nodes
```

Mind that, since we provisioned two groups of nodes, running this playbook without `--extra-vars` will default to installing on the nodes of group named `rancher`.

### 3. Install Rancher

Use the appropriate playbook to install Rancher on the appropriate nodes:

```bash
ansible-playbook -i inventory/inventory.yml playbooks/deploy/rancher-helm-deploy-playbook.yml
```

The use of additional flags is not needed here because this playbook will be applied on the nodes on the group named `rancher`.

### 4. Add cluster as downstream to Rancher

Use the appropriate playbook to add the configured downstream cluster to the configured Rancher instance.

```bash
ansible-playbook -i inventory/inventory.yml playbooks/deploy/rancher-helm-deploy-playbook.yml --extra-vars="target=airgap_nodes:downstream"
```

From here just check that Rancher is running and the cluster has been properly added:

```
to be done
```
