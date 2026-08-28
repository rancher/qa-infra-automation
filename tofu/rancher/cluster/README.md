# Downstream Rancher Cluster rke2/k3s module

This module deploys a downstream cluster on your rancher setup

## Prerequisites

* An api_key from your rancher setup
* tofu installed on your client machine
* valid credentials to a provider that works with rancher's node drivers (i.e. aws, harvester)
* For `cloud_provider = "aws"`: `node_config.aws_vpc`/`aws_subnet` are required (pre-existing). `node_config.aws_security_group` is optional — if omitted, this module provisions its own ephemeral security group, created on `apply` and destroyed on `destroy`, alongside every other resource (see "Ephemeral networking" below).

## Usage

1.  **Create a Workspace:**

    ```bash
    tofu workspace new <workspace_name>
    ```

2.  **Select the Workspace:**

    ```bash
    tofu workspace select <workspace_name>
    ```

3.  **Create the downstream cluster**
    * see the [variables section](#sample) to configure the cluster
    ```bash
    tofu -chdir=tofu/rancher/cluster apply -auto-approve -var-file=/path/to/vars.tfvars -var-file=$REPO_ROOT/ansible/rancher/generated.tfvars
    ```
    omit the last -var-file if not using rancher installed via ansible

    Create a `vars.tfvars` file or use the `-var` flag to provide values for the variables defined in `variables.tf`.

4.  **Destroy the downstream cluster:**

    ```bash
    tofu -chdir=tofu/rancher/cluster destroy -auto-approve -var-file=/path/to/vars.tfvars -var-file=$REPO_ROOT/ansible/rancher/generated.tfvars
    ```

    Use the same `vars.tfvars` file or `-var` flags used during `apply`.

## Using `make` (from the repo root)

The repository `Makefile` wraps the commands above and auto-loads
`ansible/rancher/default-ha/generated.tfvars` for `fqdn`/`api_key`:

```bash
# Plan / create (prompts unless AUTO_APPROVE=yes)
make downstream-tofu-plan    DOWNSTREAM_TFVARS=/path/to/vars.tfvars
make downstream-tofu         DOWNSTREAM_TFVARS=/path/to/vars.tfvars

# Destroy (prompts unless AUTO_APPROVE=yes)
make downstream-tofu-destroy DOWNSTREAM_TFVARS=/path/to/vars.tfvars

# Show outputs
make downstream-tofu-output  DOWNSTREAM_TFVARS=/path/to/vars.tfvars
```

Override `RANCHER_TFVARS=<path>` if your Rancher outputs live elsewhere, and
`WORKSPACE=<name>` to isolate multiple downstream clusters (one workspace per
cluster). The targets validate that both var files exist before invoking tofu.

## Outputs
Refer to [outputs.tf](./outputs.tf) for a list of exported values.

## Ephemeral networking (AWS only — security group)

`node_config.aws_vpc`/`aws_subnet` are required (pre-existing) when
`cloud_provider = "aws"`. When `node_config.aws_security_group` is left
unset/empty, this module provisions its own equivalent instead:

* A security group opening SSH (22) and the LB listener ports (80, 443, 6443,
  9345) to `ephemeral_sg_ingress_cidrs` (required, no default — must be
  specific /32s or narrower CIDRs; `0.0.0.0/0`/`::/0` are rejected), plus full
  intra-group traffic
* Egress restricted to `ephemeral_sg_egress_cidrs` (defaults to the VPC's own
  CIDR when unset; `0.0.0.0/0`/`::/0` are rejected here too — extend with
  additional specific CIDRs if nodes need broader outbound access, e.g. via a
  NAT gateway/proxy)

## Sample `vars.tfvars`
this will highly depend on the selected provider. This example includes options for aws. Sensitive info is omitted.

```tofu

kubernetes_version = "v1.32.5+rke2r1"
is_network_policy = false
machine_pools = [ {
  control_plane_role = true
  worker_role = true
  etcd_role = true
  quantity = 1
} ]
create_new = true
generate_name = "tf"
node_config = {
  aws_access_key = ""
  aws_secret_key= ""

  aws_ami = "ami-0e01311d1f112d4d0"

  aws_instance_type = "t3a.2xlarge"
  # aws_security_group omitted -> module creates its own ephemeral security
  # group, destroyed automatically on `destroy`.

  aws_subnet = "subnet-123"
  aws_availability_zone = "b"
  aws_vpc = "vpc-123"
  aws_region    = "us-west-1"

  aws_volume_size   = 50
  aws_volume_type   = "gp3"
  aws_hostname_prefix  = "tf"
  aws_route53_zone  = "qa.rancher.space"
}
# Top-level module inputs (not part of node_config) for the ephemeral SG:
ephemeral_sg_ingress_cidrs = ["203.0.113.10/32"]   # jumpbox/bastion/office CIDR(s) for SSH + LB ports

fqdn = "https://rancher-setup.example"
api_key =  ""

cloud_provider = "aws"
insecure = true
```