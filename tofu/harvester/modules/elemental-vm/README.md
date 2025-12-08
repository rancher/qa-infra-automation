# Elemental VMs on Harvester

This module provisions and manages Elemental virtual machines on Harvester using OpenTofu (Terraform-compatible).

---

## Overview

This module allows you to deploy a customizable cluster of Elemental-based virtual machines on Harvester.
It handles instance creation and the Elemental instalation automatically.

---

## Prerequisites

Before using this module, ensure that you have:

- An **Elemental image URL** hosted in an S3 bucket with public access, follow the instructions in the referenced [README.md](../../../aws/modules/s3/README.md) to create S3 with public access.
- A **Rancher** installation with Elemental properly configured, refer to the corresponding [README.md](../../../../ansible/rancher/downstream/elemental/harvester/README.md) for instructions on enabling Elemental in Rancher and upload elemental image into S3 bucket.
- A valid **Harvester kubeconfig** file.

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
image_url                 = "<public S3 image URL>"
harvester_kubeconfig_file = "<path to Harvester kubeconfig>"
user_data_base64          = "I2Nsb3VkLWNvbmZpZwpwYWNrYWdlX3VwZGF0ZTogdHJ1ZQpwYWNrYWdlczoKICAtIHFlbXUtZ3Vlc3QtYWdlbnQKcnVuY21kOgogIC0gLSBzeXN0ZW1jdGwKICAgIC0gZW5hYmxlCiAgICAtIC0tbm93CiAgICAtIHFlbXUtZ3Vlc3QtYWdlbnQuc2VydmljZQo="

```