# Quickstart

## Prerequisites

1. OpenTofu: Ensure `tofu` is installed and in your path.
2. SSH Key Pair: A local SSH public key to inject into the nodes.

## Steps

### Step 1: Clone and Navigate

Clone the repository and move to the relevant directory.

```sh
git clone https://github.com/rancher/qa-infra-automation.git
cd rancher/qa-infra-automation
```

### Step 2: Configuration

Navigate to the module directory to understand the required inputs:

```sh
cd tofu/aws/modules/cluster_nodes
```

**Critical Step:** Open `variables.tf` in this directory to confirm the exact variable names. The configuration below is a template based on standard patterns in this repo.

Create a file named `terraform.tfvars` in this directory.

`terraform.tfvars` Template:

```conf
aws_access_key        = "yourkey" # Replace with your AWS Access Key ID
aws_secret_key        = "yoursecret" # Replace with your AWS Secret Access Key
aws_hostname_prefix   = "quickstart" # Replace with your shortname -- helps with cleanup and resource utilization
aws_region            = "us-east-2"
aws_route53_zone      = "qa.rancher.space"
aws_ami               = "ami-01de4781572fa1285" # us-east-2 SLES 15 SP7
aws_ssh_user          = "ec2-user" # Default user for above AMI
instance_type         = "t3a.medium" # Low-cost option, 2cpu 4GB
aws_vpc               = "vpc-" # Fill in your VPC
aws_subnet            = "subnet-" # Fill in your subnet
aws_security_group    = ["sg-"] # Fill in your security group ID
airgap_setup          = false
proxy_setup           = false
aws_volume_size       = 40
aws_volume_type       = "gp3"
public_ssh_key        = "/path/to/.ssh/id_rsa.pub" # Fill in path to your public key
nodes = [
  # {
  #   count = 3
  #   role  = ["etcd"]
  # },
  # {
  #   count = 2
  #   role  = ["cp"]
  # },
  # {
  #   count = 3
  #   role  = ["worker"]
  # }
  {
    count = 3
    role = ["etcd", "cp", "worker"]
  }
]
```

### Step 3: Deploy with Tofu

Initialize the module, verify the plan, and apply.

```sh
# Initialize Tofu
tofu init

# Check the execution plan
tofu plan

# Apply the infrastructure
tofu apply
```

### Step 4: Integration with Ansible (Post-Deployment)

This module is designed to chain its Tofu outputs into Ansible inventories. If you plan to run the playbooks located in `ansible/`, follow these steps:

1. Set the Node Source Variable: Tell the automation scripts where your Terraform/Tofu state lives.

```
export TERRAFORM_NODE_SOURCE="tofu/aws/modules/cluster_nodes"
```

2. Generate Inventory: Use envsubst to generate the Ansible inventory file from the desired template in the root of the repo. Example below shown for the template in `rke2/default`.

```
# From the repository root
envsubst < ansible/rke2/default/inventory-template.yml > terraform-inventory.yml
```

### Step 5: Cleanup

To destroy the infrastructure when finished:

```
tofu destroy
```
