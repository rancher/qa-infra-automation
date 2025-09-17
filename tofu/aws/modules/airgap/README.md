# AWS Airgap tofu Module

This module deploys airgap rancher on AWS.

## Prerequisites

* AWS account configured with appropriate credentials (for provider and S3 backend).
* tofu installed.
* S3 bucket for remote tfstate (create one with IAM permissions for Terraform to read/write).

## S3 Backend for tfstate Management

This module uses an S3 backend to store tfstate remotely. This automatically uploads the state to S3 after `tofu apply` and updates it on `tofu destroy`. No AWS CLI is needed; it uses the AWS provider.

### Setup

1. Create an S3 bucket (e.g., `airgap-terraform-state`) in your desired region with versioning enabled (optional but recommended).
   - Ensure your AWS credentials have s3:GetObject, s3:PutObject, s3:DeleteObject permissions on the bucket.

2. Edit `backend.tfvars` with your bucket details:
   ```
   bucket = "your-s3-bucket-name"
   key    = "airgap/terraform.tfstate"
   region = "us-east-2"  # Bucket region
   ```

3. Initialize the backend:
   ```
   tofu init -backend-config=backend.tfvars
   ```

### Toggling S3 Backend On/Off

The S3 backend is opt-in and can be toggled:

- **On (S3 State)**: Run `tofu init -backend-config=backend.tfvars`. State is stored in S3 on apply/destroy.
- **Off (Local State, Default)**: Run `tofu init` without backend config. Uses local `terraform.tfstate` file—no S3 upload.
- **Switching Back to Local**: Run `tofu init -reconfigure` (without backend config). Download state from S3 first if needed to avoid loss.

For dynamic toggling, use workspaces (e.g., "s3" workspace with backend, "local" without).

### Usage with Backend

After init, the tfstate is stored in S3:
- `tofu apply -var-file="terraform.tfvars"`: Applies infrastructure and uploads state to S3.
- `tofu destroy -var-file="terraform.tfvars"`: Destroys infrastructure and updates state in S3.

For workspaces, the key will be prefixed (e.g., "env:/workspace/terraform.tfstate").

## Usage (Infrastructure Deployment)

1. **Create a Workspace:**

   ```
   tofu workspace new <workspace_name>
   ```

2. **Select the Workspace:**

   ```
   tofu workspace select <workspace_name>
   ```

3. **Apply the Configuration:**

   ```
   tofu apply -var-file="terraform.tfvars"
   ```
   or
   ```
   tofu apply -var="<variable_name>=<variable_value>"
   ```

   Create a `terraform.tfvars` file or use the `-var` flag to provide values for the variables defined in `variables.tf`.

4. **Destroy the Infrastructure:**

   ```
   tofu destroy -var-file="terraform.tfvars"
   ```
   or
   ```
   tofu destroy -var="<variable_name>=<variable_value>"
   ```

   Use the same `terraform.tfvars` file or `-var` flags used during `apply`.

## Variables

Refer to `variables.tf` for a list of configurable variables.

## Outputs

Refer to `outputs.tf` for a list of exported values.

## Sample `terraform.tfvars`

```
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
```
