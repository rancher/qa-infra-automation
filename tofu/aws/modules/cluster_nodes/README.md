# AWS Cluster Nodes Terraform Module

This module deploys a set of cluster nodes on AWS.

## Prerequisites

* AWS account configured with appropriate credentials.
* Terraform installed.
* A pre-existing VPC and Subnet (`aws_vpc`/`aws_subnet` are required).
  Optional: a pre-existing Security Group. If you don't provide
  `aws_security_group`, the module provisions its own ephemeral security
  group — created fresh on `apply` and destroyed on `destroy`, alongside every
  other resource in this module (see "Ephemeral networking" below).

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

### Node Groups

The `nodes` variable defines cluster node groups. Each group accepts:

| Field | Type | Required | Description |
|-------|------|----------|------------- |
| `count` | number | Yes | Number of instances |
| `role` | list(string) | Yes | Node roles: `["etcd"]`, `["cp"]`, `["worker"]`, or combined like `["etcd", "cp", "worker"]` |
| `instance_type` | string | No | Override the global `instance_type` for this node group |

The first node in the first group with `etcd` role becomes the `master` node.

**Important:** Nodes with the same role must be in a single group (e.g., `{ count = 2, role = ["etcd"] }`). Splitting them into multiple groups causes duplicate hostname conflicts.

### Resource name length

`aws_hostname_prefix` seeds every AWS resource name the module creates: the key
pair (`tf-<prefix>-<12 hex chars>`), the security groups
(`tf-<prefix>-sg`, `tf-<prefix>-ssh`), the NLB (`<prefix>-nlb`), the target
groups (`<prefix>-tg-<port>`) and the DNS record. AWS caps most resource names at
63 characters and load balancer and target group names cap at **32**.
So the prefix has to leave room for the decoration the module adds:
**at most 24 characters, or 17 with `random_name_suffix = true`** (the
suffix adds 7). The module validates this during `tofu plan` and reports the
budget instead of letting AWS reject a name halfway through `tofu apply`.

### Ephemeral networking (security group)

`aws_vpc` and `aws_subnet` are required (pre-existing). `aws_security_group`
is optional — when left unset (defaults to `[]`), the module provisions its
own equivalent instead:

* A security group opening SSH (22, restricted to `ephemeral_sg_ingress_cidrs`),
  plus full intra-group traffic
* Egress: all protocols, all ports, to `0.0.0.0/0` (a single unrestricted
  outbound rule). `ephemeral_sg_egress_cidrs` is kept only for backward
  compatibility with existing callers and no longer has any effect.
  **Upgrade note:** for any already-`apply`d deployment, this rule replaces
  several previously separate egress rules. One (`ephemeral_self_egress`) is
  migrated in place via a `moved` block; the rest (default/listener/HTTP/
  HTTPS/DNS and the per-node RKE2/LB egress rules) have no equivalent target
  and will show as destroyed on the next `plan`/`apply`, briefly narrowing
  egress until the new rule is created.
* Inbound access on TCP/80 and TCP/443 from `ephemeral_sg_ingress_cidrs`
  plus the VPC's own CIDR (RKE2/Rancher NLB health checks, which originate
  from AWS-managed ENIs inside the VPC rather than instances in this SG).
  Node-to-node traffic addressed via public IPs egresses out through the
  IGW and re-enters tagged with the *source node's public IP* - not the VPC
  CIDR and not `ephemeral_sg_ingress_cidrs` - so a single all-protocol,
  all-port `/32` ingress rule per node (`rke2_node_ingress`) is additionally
  created once each node's public IP is known; ingress on 80/443 never opens
  to `0.0.0.0/0`. Egress for this hairpin traffic is already covered by the
  unrestricted `0.0.0.0/0` egress rule above, so no per-node egress rule is
  needed.
  **Upgrade note:** for any already-`apply`d deployment, `rke2_node_ingress`
  replaces the previously separate `rke2_lb_node_ingress` (ports 80/443) and
  `rke2_api_node_ingress` (ports 6443/9345) resources, each keyed per
  `"<port>-<node>"` pair. Because multiple old keys collapse into one new
  key per node, there is no 1:1 `moved` mapping - the old rules will show as
  destroyed on the next `plan`/`apply`, briefly dropping node-to-node ingress
  on 80/443/6443/9345 until the new rule is created.

### SSH access (avoiding prefix-list propagation lag)

`create_ssh_security_group` (default `false`) — opt in to have the module create a
**dedicated** security group that grants SSH (port 22) from a list of **stable** CIDRs
(`ssh_allowed_cidrs`) plus the VPC's own CIDR, attached to every node **alongside**
`aws_security_group`.

**Enable this when your jumpbox/bastion/office IP is allowed SSH only through a
*managed prefix list* referenced by `aws_security_group`.** AWS propagates
prefix-list SG rules to each instance's ENI **asynchronously**, so on freshly-launched
instances one random ENI can lag or land on a stale list version and silently drop SSH
SYN packets to that node until propagation completes. This surfaces as *"one node
randomly unreachable on SSH right after `apply`"* — host firewall open, VPC-internal
SSH working, but a TCP connect timeout from the jumpbox, with a **different node
affected each build**. Plain CIDR SG rules, by contrast, are realized on the ENI
**immediately at launch**, so SSH always works.

AWS security groups are **additive** (a flow is allowed if *any* attached SG allows
it), so this layers on top of `aws_security_group` — the existing RKE2/Rancher port
matrix in the shared SG is left untouched. The new SG is owned by this module and is
destroyed automatically on `terraform destroy`.

```terraform
create_ssh_security_group = true
ssh_allowed_cidrs         = ["45.33.107.248/32"]   # jumpbox / bastion / office egress
```

VPC-internal SSH is allowed automatically (from the VPC CIDR), so node-to-node access
(e.g. Ansible run from a node, or reaching one node from another) always works
regardless of this setting. The created SG's ID is exported as `ssh_security_group_id`.

## Outputs

Refer to `outputs.tf` for a list of exported values.

## Sample `terraform.tfvars`

### All-in-one (simplest — ephemeral security group)

```terraform
aws_access_key        = "key"
aws_secret_key        = "secretkey"
aws_region            = "us-west-1"
aws_route53_zone      = "qa.rancher.space"
aws_ami               = "ami-"
instance_type         = "t3a.medium"
aws_vpc               = "vpc-"
aws_subnet            = "subnet-"
# aws_security_group omitted -> module creates its own ephemeral security
# group, destroyed automatically on `destroy`.
ephemeral_sg_ingress_cidrs = ["203.0.113.10/32"]   # jumpbox/bastion/office CIDR(s) for SSH + NLB ports
airgap_setup          = false
proxy_setup           = false
aws_volume_size       = 40
aws_volume_type       = "gp3"
aws_hostname_prefix   = "hostnameprefix"
aws_ssh_user          = "ec2-user"
public_ssh_key        = "sshkey"
# Optional: grant SSH from a stable /32 (jumpbox/bastion) via a dedicated SG.
# Avoids managed-prefix-list propagation lag — see "SSH access" above.
# create_ssh_security_group = true
# ssh_allowed_cidrs         = ["203.0.113.10/32"]
nodes = [
  {
    count = 3
    role  = ["etcd", "cp", "worker"]
  }
]
```

### Bring your own VPC/subnet/security group

```terraform
aws_access_key        = "key"
aws_secret_key        = "secretkey"
aws_region            = "us-west-1"
aws_route53_zone      = "qa.rancher.space"
aws_ami               = "ami-"
instance_type         = "t3a.medium"
aws_vpc               = "vpc-"
aws_subnet            = "subnet-"
aws_security_group    = ["sg-"]
airgap_setup          = false
proxy_setup           = false
aws_volume_size       = 40
aws_volume_type       = "gp3"
aws_hostname_prefix   = "hostnameprefix"
aws_ssh_user          = "ec2-user"
public_ssh_key        = "sshkey"
nodes = [
  {
    count = 3
    role  = ["etcd", "cp", "worker"]
  }
]
```

### Split topology with per-role instance types

Use larger instances for etcd nodes (RKE2 v1.35+ requires cgroup v2, which needs SLES 15 SP5+):

```terraform
aws_access_key        = "key"
aws_secret_key        = "secretkey"
aws_region            = "us-west-1"
aws_route53_zone      = "qa.rancher.space"
aws_ami               = "ami-"          # SLES 15 SP5+ for cgroup v2
instance_type         = "t3a.medium"    # Default for all nodes
aws_vpc               = "vpc-"
aws_subnet            = "subnet-"
aws_security_group    = ["sg-"]
airgap_setup          = false
proxy_setup           = false
aws_volume_size       = 40
aws_volume_type       = "gp3"
aws_hostname_prefix   = "hostnameprefix"
aws_ssh_user          = "ec2-user"
public_ssh_key        = "sshkey"
nodes = [
  {
    count         = 2
    role          = ["etcd"]
    instance_type = "t3a.xlarge"   # 4 vCPU / 16 GB — etcd needs more RAM
  },
  {
    count         = 3
    role          = ["cp"]
    instance_type = "t3a.large"    # 2 vCPU / 4 GB
  },
  {
    count = 3
    role  = ["worker"]             # Uses global instance_type (t3a.medium)
  }
]
```
