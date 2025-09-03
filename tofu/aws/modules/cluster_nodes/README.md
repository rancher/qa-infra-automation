# AWS Cluster Nodes Terraform Module

This module deploys a set of cluster nodes on AWS.

## Prerequisites

* AWS account configured with appropriate credentials.
* AWS account configured already with a VPC, Subnet, and Security Group that you will use as variables in this module.
* Terraform installed.

## Usage

1.  **Create a Workspace:**

    ```bash
    terraform workspace new <workspace_name>
    ```

2.  **Select the Workspace:**

    ```bash
    terraform workspace select <workspace_name>
    ```

3.  **Initialize the Terraform:**

    ```bash
    terraform init
    ```

4.  **Apply the Configuration:**

    ```bash
    terraform apply -var-file="terraform.tfvars"
    ```
    or
    ```bash
    terraform apply -var="<variable_name>=<variable_value>"
    ```

    Create a `terraform.tfvars` file or use the `-var` flag to provide values for the variables defined in `variables.tf`.

5.  **Destroy the Infrastructure:**

    ```bash
    terraform destroy -var-file="terraform.tfvars"
    ```
    or
    ```bash
    terraform destroy -var="<variable_name>=<variable_value>"
    ```

    Use the same `terraform.tfvars` file or `-var` flags used during `apply`.

## Variables

Refer to `variables.tf` for a list of configurable variables.

## Outputs

Refer to `outputs.tf` for a list of exported values.

## Sample `terraform.tfvars`

```terraform
aws_access_key        = "key"
aws_secret_key        = "secretkey"
aws_region            = "us-west-1"
aws_route53_zone      = "qa.rancher.space"
aws_ami               = "ami-"
instance_type         = "t3.xlarge"
aws_vpc               = "vpc-"
aws_subnet            = "subnet-"
aws_security_group    = ["sg-"]
airgap_setup          = false
proxy_setup           = false
aws_volume_size       = 500
aws_volume_type       = "gp3"
aws_hostname_prefix   = "hostnameprefix"
aws_ssh_user          = "ec2-user"
user_id               = "user_id"
public_ssh_key        = "sshkey"
nodes = [
  {
    count = 1
    role  = ["etcd"]
  },
  {
    count = 1
    role  = ["cp"]
  },
  {
    count = 3
    role  = ["worker"]
  }
  # {
  #   count = 1
  #   role = ["etcd"]
  # }
]
