# AWS Airgap tofu Module

This module deploys airgap rancher on AWS.

## Prerequisites

* AWS account configured with appropriate credentials.
* tofu installed.

## Usage

1. **Configure S3 Upload (Optional but Recommended):**
   Update `terraform.tfvars` with your S3 bucket, key, and region values.

2. **Create a Workspace:**

   ```bash
   tofu workspace new <workspace_name>
   ```

3. **Select the Workspace:**

   ```bash
   tofu workspace select <workspace_name>
   ```

4. **Apply the Configuration:**

   ```bash
   tofu apply -var-file="terraform.tfvars"
   ```
   or
   ```bash
   tofu apply -var="<variable_name>=<variable_value>"
   ```

   Create a `terraform.tfvars` file or use the `-var` flag to provide values for the variables defined in `variables.tf`. After apply, the tfstate will be automatically uploaded to the specified S3 bucket.

5. **Destroy the Infrastructure:**

   ```bash
   tofu destroy -var-file="terraform.tfvars"
   ```
   or
   ```bash
   tofu destroy -var="<variable_name>=<variable_value>"
   ```

   Use the same `terraform.tfvars` file or `-var` flags used during `apply`.

## Variables

Refer to `variables.tf` for a list of configurable variables.

**New S3 Upload Variables:**
- `s3_bucket` (string, required): Name of the S3 bucket to upload tfstate to.
- `s3_key` (string, default: "airgap/terraform.tfstate"): Path/key for the tfstate file in S3.
- `s3_region` (string, required): AWS region of the S3 bucket (e.g., "us-east-2").

## Outputs

Refer to `outputs.tf` for a list of exported values.

## Sample `terraform.tfvars`

```terraform
aws_access_key        = "key"
aws_secret_key        = "secretkey"
aws_ami               = "ami-"
instance_type         = "t3.xlarge"
aws_security_group    = ["sg-"]
aws_subnet            = "subnet-"
aws_volume_size       = 500
aws_hostname_prefix   = "hostnameprefix"
aws_region            = "us-west-1"
aws_route53_zone      = "qa.rancher.space"
aws_ssh_user          = "ec2-user"
aws_vpc               = "vpc-"
user_id               = "user_id"
ssh_key               = "sshkey"
ssh_key_name          = "sshkeyname"