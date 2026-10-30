# AWS Cluster Nodes Terraform Module

This module deploys a set of cluster nodes on AWS.

## Prerequisites

* AWS account configured with appropriate credentials.
* AWS account configured already with a VPC, Subnet, and Security Group that you will use as variables in this module.
* Terraform installed.

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

The first node in the first group with the `etcd` role becomes the `master` node.
Clusters with no `etcd` node (external datastore) fall back to the first `cp` node.
At least one node group must include the `cp` role.

**Important:** Nodes with the same role must be in a single group (e.g., `{ count = 2, role = ["etcd"] }`). Splitting them into multiple groups causes duplicate hostname conflicts.

### Bastion host

Set `no_of_bastion_nodes = 1` to provision an SSH jump host. It attaches the same
`aws_security_group` list as the cluster nodes: those groups are managed centrally
in AWS with a maintained source-CIDR allow-list, so the module does not create or
own security groups.

The module never copies the cluster SSH private key onto the bastion; Ansible
reaches the nodes with an SSH `ProxyCommand` that keeps the key on the controller.

### IPv6-only DNS

When `enable_public_ip = false` the nodes are IPv6-only. Reaching IPv4-only
endpoints (container registries, `get.rke2.io`, ...) then needs DNS64 and NAT64.

By default the module takes over host DNS: instance user data stops
`systemd-resolved` and writes `ipv6_dns64_resolvers` into `/etc/resolv.conf`.
The default resolver is the public `nat64.net` service (`2a00:1098:2c::1`),
which is what these QA clusters use today.

Three supported configurations:

| Goal | Settings |
|------|----------|
| Public DNS64 (default) | nothing to set |
| VPC-native DNS64 | `ipv6_dns64_resolvers = ["<vpc +2 address>"]` — enable DNS64 on the subnet and add a `64:ff9b::/96` route to a NAT gateway |
| Leave host DNS alone | `ipv6_manage_dns = false` |

`ipv6_manage_dns = false` suppresses the `systemd-resolved` and `/etc/resolv.conf`
changes entirely, for images that manage their own resolver or VPCs that already
hand out a DNS64 resolver via DHCPv6. `ipv6_dns64_resolvers` is then ignored.

Independently of this setting, IPv6-only nodes always get an `/etc/hosts` fixup
so they can resolve their own hostname: there is no `127.0.0.1` entry to match
against once the node has no IPv4 address.

## Outputs

Refer to `outputs.tf` for a list of exported values.

## Sample `terraform.tfvars`

### All-in-one (simplest)

```terraform
# aws_access_key/aws_secret_key are optional; omit them to use the AWS
# provider's standard credential chain.
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
no_of_bastion_nodes = 1
aws_bastion_subnet  = "subnet-id"

# Dualstack or IPv6 Only deployments
enable_ipv6  = true # Associate ipv6 ip to nodes and bastion node.
enable_public_ip  = true # Associate ipv4 public ip to nodes
kube_api_host_ipv6 = false # Set for dualstack ipv4/ipv6 kube_api_host value in dualstack scenarios.
```
Refer to tofu/aws/modules/dualstack/examples/notes.md for setting these variables in detail.

### Split topology with per-role instance types

Use larger instances for etcd nodes (RKE2 v1.35+ requires cgroup v2, which needs SLES 15 SP5+):

```terraform
# aws_access_key/aws_secret_key are optional; omit them to use the AWS
# provider's standard credential chain.
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
no_of_bastion_nodes = 1
aws_bastion_subnet = "subnet-0377a1ca391d51cae"

# Dualstack or IPv6 Only deployments
enable_ipv6  = true # associate ipv6 to nodes and bastion node.
enable_public_ip  = true # Associate ipv4 public ip to nodes
kube_api_host_ipv6 = false # Set for choosing ipv4/ipv6 value for kube_api_host in dualstack scenario. 
```
Refer to tofu/aws/modules/dualstack/examples/notes.md for further information on these variables. 

## Dualstack vars.yaml file content: 
`$ cat ansible/rke2/default/vars.yaml`
```
# rke2 version and installation settings
kubernetes_version: 'v1.36.2+rke2r1'

# kubeconfig file
kubeconfig_file: './kubeconfig.yaml'

# cni configuration
cni: "calico"

# node token file for cluster communication
node_token_file: "/tmp/node_token.txt"

# Server configuration flags (applied to server/control-plane nodes)
# See https://docs.rke2.io/reference/server_config for all options

server_flags: |
  ingress-controller: traefik
  cluster-cidr: 10.42.0.0/16,2001:cafe:42:0::/56
  service-cidr: 10.43.0.0/16,2001:cafe:43:0::/112
  node-ip: "{{ ansible_host }},{{ ansible_host_ipv6 }}"

worker_flags: |
  node-ip: "{{ ansible_host }},{{ ansible_host_ipv6 }}"
```
