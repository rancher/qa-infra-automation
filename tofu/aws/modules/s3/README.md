# S3 Module

This module provisions and manages Amazon S3 buckets using OpenTofu (Terraform-compatible).

---

## Overview

Use this module to create and manage an S3 bucket with optional public access.
It supports both public and private bucket configurations, depending on your requirements.

---

## Prerequisites

Before using this module, ensure that you have:

- An AWS account with appropriate permissions to create and manage S3 resources.
- OpenTofu installed and available in your environment.

---

## Usage

### 1. Create a new workspace

```bash
tofu workspace new <workspace_name>
```

### 2. Select the workspace

```bash
tofu workspace select <workspace_name>
```

### 3. Initialize the module

```bash
tofu init
```

### 4. Apply the configuration

```bash
tofu apply -var="variable_name=value"
```

## 5. Destroy the infrastructure

```bash
tofu destroy -var-file="terraform.tfvars"
```
## Outputs

This setup does not produce any direct outputs.

## Sample terraform.tfvars

```
bucket_name          = "<s3-bucket-name>"
aws_access_key       = "<aws-access-key>"
aws_secret_key       = "<aws-secret-key>"
aws_region           = "<aws-region>"
block_public_access  = false

```