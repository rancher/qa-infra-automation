# Quickstart

> **📖 Looking for an end-to-end guide?** See [RKE2 on AWS](../../../docs/guides/rke2-default-aws.md) for step-by-step instructions covering infrastructure through cluster verification.

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
aws_ami               = "ami-id" # us-east-2 SLES 15 SP7
aws_ssh_user          = "ec2-user" # Default user for above AMI
instance_type         = "t3a.medium" # Low-cost option, 2cpu 4GB
aws_vpc               = "vpc-id" # Fill in your VPC
aws_subnet            = "subnet-id" # Fill in your subnet
aws_security_group    = ["sg-id"] # Fill in your security group ID
airgap_setup          = false
proxy_setup           = false
aws_volume_size       = 40
aws_volume_type       = "gp3"
public_ssh_key        = "/path/to/.ssh/id_rsa.pub" # Fill in path to your public key
private_ssh_key       = "/path/to/jenkins.pem" # generate the .pem file from .pub file if needed. 
key_name              = "jenkins"
nodes = [
  # Split topology with per-role instance types:
  # {
  #   count         = 3
  #   role          = ["etcd"]
  #   instance_type = "t3a.xlarge"  # etcd needs more RAM
  # },
  # {
  #   count         = 2
  #   role          = ["cp"]
  #   instance_type = "t3a.large"
  # },
  # {
  #   count = 1
  #   role  = ["worker"]
  # }

  # All-in-one (simplest):
  {
    count = 3
    role = ["etcd", "cp", "worker"]
  }
]

no_of_bastion_nodes = 1
aws_bastion_subnet = "subnet-id"

# Dualstack or IPv6 Only deployments
enable_ipv6  = true
enable_public_ip  = true # Associate ipv4 public ip address
kube_api_host_ipv6 = false # dualstack setup may use kube_api_host as ipv4 or ipv6. Change per scenario being tested.
```

### Step 2: Deploy with Tofu

Initialize the module, verify the plan, and apply. Run from the root of this repo.

```sh
# Initialize Tofu
tofu -chdir=tofu/aws/modules/dualstack init

# Check the execution plan
tofu -chdir=tofu/aws/modules/dualstack plan

# Apply the infrastructure
tofu -chdir=tofu/aws/modules/dualstack apply
```

### Step2a. Deploy using make commands

```
make infra-up ENV=dualstack # Deploys setup/inventory and creates inventory.yml file
make cluster ENV=dualstack # Performs rke2 install and creates rke2 cluster
make infra-output ENV=dualstack # to get output/setup information
make status ENV=dualstack # to get nodes and pods status of rke2 cluster. 
```
Note: May have to login to bastion node for ipv6 scenarios to get kubectl outputs. ~/.kube/config is updated in bastion node with rke2 cluster's kubeconfig file.

### Step 3: Cleanup

To destroy the infrastructure when finished:

```sh
tofu -chdir=tofu/aws/modules/dualstack destroy
```
or 
```
make infra-down ENV=dualstack
```
