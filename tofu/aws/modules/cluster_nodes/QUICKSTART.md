# Quickstart

## Prerequisites

1. OpenTofu: Ensure `tofu` is installed and in your path.
2. SSH Key Pair: A local SSH public key to inject into the nodes.

## Steps

### Step 1: Configuration

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

### Step 2: Deploy with Tofu

Initialize the module, verify the plan, and apply. Run from the root of this repo.

```sh
# Initialize Tofu
tofu -chdir=tofu/aws/modules/cluster_nodes init

# Check the execution plan
tofu -chdir=tofu/aws/modules/cluster_nodes plan

# Apply the infrastructure
tofu -chdir=tofu/aws/modules/cluster_nodes apply
```

### Step 3: Cleanup

To destroy the infrastructure when finished:

```sh
tofu -chdir=tofu/aws/modules/cluster_nodes destroy
```
