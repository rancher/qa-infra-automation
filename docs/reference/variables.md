# Ansible Variables Reference

All configurable variables across playbooks and roles. Variables are set in `vars.yaml` files or in the inventory.

## RKE2 Default (`ansible/rke2/default/vars.yaml`)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `kubernetes_version` | Yes | — | RKE2 version (e.g., `v1.34.2+rke2r1`). See [releases](https://github.com/rancher/rke2/releases). |
| `cni` | Yes | — | CNI plugin: `calico`, `canal`, or `cilium` |
| `kubeconfig_file` | No | `./kubeconfig.yaml` | Local path to save the kubeconfig |
| `channel` | No | `stable` | RKE2 release channel: `stable`, `latest`, `testing` |
| `install_method` | No | `online` | Installation method: `online` or `airgap` |
| `server_flags` | No | — | Extra YAML config for server nodes (written to `/etc/rancher/rke2/config.yaml`) |
| `worker_flags` | No | — | Extra YAML config for agent nodes |
| `node_token_file` | No | `/tmp/node_token.txt` | Temp file for cluster join token |

### Inventory Variables (set in inventory, not vars.yaml)

| Variable | Set By | Description |
|----------|--------|-------------|
| `fqdn` | Tofu / manual | Cluster FQDN for TLS SANs |
| `kube_api_host` | Tofu / manual | Kubernetes API server IP |
| `ansible_host` | Tofu / manual | Node IP for SSH |
| `ansible_user` | Tofu / manual | SSH user |
| `rke2_node_role` | Tofu / manual | `master`, `server`, or `agent` |
| `node_roles` | Tofu / manual | List: `etcd`, `cp`, `worker` |

## K3s Default (`ansible/k3s/default/vars.yaml`)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `kubernetes_version` | Yes | — | K3s version (e.g., `v1.35.2+k3s1`). See [releases](https://github.com/k3s-io/k3s/releases). |
| `kubeconfig_file` | No | `./kubeconfig.yaml` | Local path to save the kubeconfig |
| `channel` | No | `stable` | K3s release channel: `stable`, `latest`, `testing` |
| `server_flags` | No | — | Extra YAML config for server nodes |
| `worker_flags` | No | — | Extra YAML config for agent nodes |
| `node_token_file` | No | `/tmp/node_token.txt` | Temp file for cluster join token |

## RKE2 Airgap (`ansible/rke2/airgap/inventory/group_vars/all.yml`)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `rke2_version` | No | latest stable | RKE2 version to install |
| `ssh_private_key_file` | Yes | `~/.ssh/id_rsa` | SSH key for bastion proxy |
| `cni` | No | `canal` | CNI plugin: `canal`, `calico`, `cilium`, `multus`, `none` |
| `cluster_cidr` | No | `10.42.0.0/16` | Pod network CIDR |
| `service_cidr` | No | `10.43.0.0/16` | Service network CIDR |
| `cluster_dns` | No | `10.43.0.10` | Cluster DNS IP |
| `rke2_server_options` | No | (see template) | Additional server config (YAML block) |
| `rke2_agent_options` | No | `""` | Additional agent config (YAML block) |
| `enable_private_registry` | No | `false` | Configure private registry on nodes |
| `deploy_rancher` | No | `true` | Deploy Rancher after RKE2 install |
| `rancher_hostname` | Conditional | LB hostname | FQDN for Rancher UI |
| `rancher_bootstrap_password` | Conditional | — | Rancher initial admin password |
| `rancher_image_tag` | No | `v2.12.2` | Rancher version |

See the [Group Vars Guide](../../ansible/rke2/airgap/docs/configuration/GROUP_VARS_GUIDE.md) for the complete list.

## Rancher HA (`ansible/rancher/default-ha/vars.yaml`)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `rancher_version` | Yes | — | Rancher chart version (e.g., `v2.13.2` or `latest`) |
| `rancher_image_tag` | Yes | — | Rancher Docker image tag |
| `cert_manager_version` | Yes | — | cert-manager version (no `v` prefix) |
| `fqdn` | Yes | — | Rancher UI FQDN |
| `bootstrap_password` | Yes | — | First-time setup password |
| `password` | Yes | — | Permanent admin password |
| `kubeconfig_file` | Conditional | auto-detected | Path to cluster kubeconfig (set automatically by `make rancher`) |

### Upgrade Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `upgrade_mode` | No | `false` | Set to `true` to run upgrade flow |
| `rancher_chart_repo_upgrade` | Conditional | — | Helm repo name for upgrade |
| `rancher_chart_upgrade_repo_url` | Conditional | — | Helm repo URL for upgrade |
| `rancher_version_upgrade` | Conditional | — | Target Rancher version |
| `rancher_image_tag_upgrade` | No | — | Target image tag |

## Tofu Variables (`terraform.tfvars`)

### AWS Cluster Nodes (`tofu/aws/modules/cluster_nodes/`)

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `aws_access_key` | Yes | — | AWS access key ID |
| `aws_secret_key` | Yes | — | AWS secret access key |
| `aws_region` | Yes | — | AWS region |
| `aws_vpc` | Yes | — | VPC ID |
| `aws_subnet` | Yes | — | Subnet ID |
| `aws_security_group` | Yes | — | List of security group IDs |
| `aws_ami` | Yes | — | AMI ID for instances |
| `aws_ssh_user` | Yes | — | Default SSH user for the AMI |
| `instance_type` | Yes | — | EC2 instance type |
| `aws_hostname_prefix` | Yes | — | Name tag prefix |
| `public_ssh_key` | Yes | — | Path to public SSH key |
| `nodes` | Yes | — | Node groups (see below) |
| `aws_route53_zone` | No | — | Route53 hosted zone for DNS |
| `aws_volume_size` | No | `40` | EBS volume size in GB |
| `aws_volume_type` | No | `gp3` | EBS volume type |
| `airgap_setup` | No | `false` | Enable airgap networking |
| `proxy_setup` | No | `false` | Enable proxy configuration |

### Node Groups Format

```hcl
nodes = [
  { count = 3, role = ["etcd", "cp", "worker"] }    # 3 all-in-one nodes
]

# Or separated roles:
nodes = [
  { count = 3, role = ["etcd"] },
  { count = 2, role = ["cp"] },
  { count = 3, role = ["worker"] }
]
```
