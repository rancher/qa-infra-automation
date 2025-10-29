# GCP Cluster Nodes Tofu Module

This module provisions and manages virtual machine instances on **Google Cloud Platform (GCP)** using **OpenTofu** (Terraform-compatible).

---

## Overview

Use this module to deploy a customizable cluster of instances on GCP.  
It handles instance creation, and SSH key generation automatically.

---

## Prerequisites

Before using this module, ensure that you have:

- A **GCP project** with the required permissions.
- A **service account key file** with sufficient IAM roles (e.g., `compute.admin`).
- **OpenTofu (or Terraform)** installed and configured.
- Your **GCP credentials** available locally.

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

The public IP of each instance is displayed in the OpenTofu output logs.
The private SSH key is automatically generated and saved to private_key.pem.

## Sample terraform.tfvars

```
boot_image               = "projects/ubuntu-os-cloud/global/images/ubuntu-minimal-2510-questing-amd64-v20251007"
machine_type             = "n2d-standard-8"
gcp_hostname_prefix      = "<hostmane prefix>"
network                  = "default"
zone                     = "us-central1-f"
project_id               = "ei-container-platform-qa"
region                   = "us-central1"
service_account_key_path = "/service_account_credential.json"
size                     = 100
tags                     = ["http-server", "https-server", "rke2-nodes"]
```