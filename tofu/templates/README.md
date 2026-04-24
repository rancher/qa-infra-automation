# Tofu Backend Templates

This directory contains Terraform backend configuration templates used by the centralized `init-backend.sh` script.

## Template Format

Templates use `__PLACEHOLDER__` format for variable substitution:

- `__BUCKET__`: S3 bucket name
- `__KEY__`: State file path in bucket
- `__REGION__`: AWS region
- `__DYNAMODB_TABLE__`: DynamoDB table for state locking (optional)
- `__ENCRYPT__`: Enable server-side encryption (true/false)
- `__PATH__`: Local filesystem path for local backend

## Adding New Backend Types

To add a new backend type:

1. Create template file: `backend-{type}.tf.tmpl`
2. Use `__PLACEHOLDER__` format for variables
3. Add handler in `../scripts/init-backend.sh`
4. Update documentation

## Available Templates

### backend-s3.tf.tmpl

S3 backend with optional DynamoDB locking:

```hcl
terraform {
  backend "s3" {
    bucket         = "__BUCKET__"
    key            = "__KEY__"
    region         = "__REGION__"
    encrypt        = "__ENCRYPT__"
    dynamodb_table = "__DYNAMODB_TABLE__"
  }
}
```

### backend-local.tf.tmpl

Local filesystem backend:

```hcl
terraform {
  backend "local" {
    path = "__PATH__"
  }
}
```
