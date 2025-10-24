# AWS Airgap tofu Module

This module deploys airgap rancher on AWS.

## Prerequisites

* AWS account configured with appropriate credentials (for provider and S3 backend).
* tofu installed.
* S3 bucket for remote tfstate (create one with IAM permissions for Terraform to read/write).

## State Backend Management
This repo supports switching Terraform state backend between S3 and local.

### Workflow
- Generate backend.tf (not committed) and run terraform init:
  - For S3:
      ./scripts/init-backend.sh s3 --bucket my-terraform-state-bucket --key envs/prod/terraform.tfstate --region us-east-1 --dynamodb-table tf-locks --encrypt true
  - For local:
      ./scripts/init-backend.sh local --path terraform.tfstate

### Switching/migrating states

- From local -> s3:
  - Back up local state: `cp terraform.tfstate terraform.tfstate.backup`
  - Run the init script with S3 options: `./scripts/init-backend.sh s3 --bucket ... --key ... --region ...`
  - Tofu will prompt to copy existing state to the new backend. 
- From s3 -> local:
  - `tofu state pull > statefile.tfstate`
  - Run init script for local `./scripts/init-backend.sh local`
  - `tofu state push statefile.tfstate`

### Important notes
- backend.tf is generated and intentionally gitignored so each developer or CI can configure their backend.
- Switching backends (local -> s3, s3 -> local) will perform a state migration when you run tofu init with the new backend config. Always back up state files first.
  - Example: to migrate local -> s3, run the s3 init command and Tofu will prompt to copy the state.
  - You can also manually export/import state:
      tofu state pull > statefile.tfstate
      tofu init -backend-config="..."   # new backend
      tofu state push statefile.tfstate
- For S3 use server-side encryption and enable versioning on the bucket. Use a DynamoDB table for state locking (prevents concurrent writes).
- CI/CD: in pipelines pass backend values as pipeline secrets and call the script or run tofu init -backend-config with environment variables / files.
- IAM: create a dedicated role/policy allowing s3:GetObject/PutObject/ListBucket/DeleteObject and dynamodb:GetItem/PutItem/DeleteItem/Query/UpdateItem for the locking table.
```
IAM policy (example)
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowS3StateOperations",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::my-terraform-state-bucket",
        "arn:aws:s3:::my-terraform-state-bucket/*"
      ]
    },
    {
      "Sid": "AllowDynamoLocking",
      "Effect": "Allow",
      "Action": [
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:DeleteItem",
        "dynamodb:Query",
        "dynamodb:UpdateItem"
      ],
      "Resource": "arn:aws:dynamodb:us-east-1:123456789012:table/tf-locks"
    }
  ]
}
```

### Best practice checklist
- Always keep generated backend.tf out of VCS.
- Use a consistent key naming scheme in S3 (e.g., <org>/<env>/<component>/terraform.tfstate).
- Enable bucket versioning and SSE.
- Use DynamoDB for locks.
- Give CI a dedicated service account/role with least privilege.



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
