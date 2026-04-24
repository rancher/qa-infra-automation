# Tofu Scripts

This directory contains centralized utility scripts for OpenTofu/Terraform operations across all modules.

## init-backend.sh

Centralized backend configuration script that generates `backend.tf` from templates and initializes the working directory.

### Usage

```bash
# From any tofu module directory
../../scripts/init-backend.sh <backend-type> [options]

# Or using make (recommended)
make backend-s3 BUCKET=my-bucket KEY=my-key REGION=us-east-1
make backend-local
```

### S3 Backend

```bash
../../scripts/init-backend.sh s3 \
  --bucket my-terraform-state \
  --key rke2-default/terraform.tfstate \
  --region us-east-1 \
  --dynamodb-table my-lock-table \
  --encrypt true
```

Or using make:
```bash
make backend-s3 BUCKET=my-terraform-state \
  KEY=rke2-default/terraform.tfstate \
  REGION=us-east-1 \
  DYNAMODB_TABLE=my-lock-table
```

### Local Backend

```bash
../../scripts/init-backend.sh local --path terraform.tfstate
```

Or using make:
```bash
make backend-local PATH=terraform.tfstate
```

### How It Works

1. Reads template from `tofu/templates/backend-{type}.tf.tmpl`
2. Substitutes placeholders with provided values
3. Writes `backend.tf` in current directory
4. Runs `tofu init -reconfigure` to apply new backend

### Adding New Backend Types

1. Create template in `tofu/templates/backend-{type}.tf.tmpl`
2. Add case handler in `init-backend.sh` for the new type
3. Update this README with usage examples

## Available Backend Types

- **s3**: AWS S3 with optional DynamoDB locking
- **local**: Local file storage

## Requirements

- OpenTofu (`tofu`) or Terraform (`terraform`) in PATH
- Appropriate cloud credentials for backend type
