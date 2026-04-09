# rke2_config

Generates RKE2 configuration files for server and agent nodes.

## Description

This role creates the RKE2 configuration directory and generates the `config.yaml` file based on node role. It supports both server (control-plane/etcd) and agent (worker) nodes with customizable configuration options.

## Requirements

- Ansible 2.10 or higher
- Root/sudo access on target nodes
- RKE2 setup completed (firewall, packages installed)

## Role Variables

Variables defined in `defaults/main.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `rke2_config_dir` | `/etc/rancher/rke2` | RKE2 configuration directory |
| `rke2_token_file` | `{{ rke2_config_dir }}/token` | Path to cluster join token file |
| `rke2_cni` | `calico` | Container Network Interface to use |
| `rke2_server_config` | See defaults | Configuration for server nodes |
| `rke2_agent_config` | See defaults | Configuration for agent nodes |
| `rke2_disable_components` | `[]` | List of components to disable |
| `rke2_additional_config` | `{}` | Additional configuration options |

### Server Configuration Defaults

```yaml
rke2_server_config:
  cni: "{{ rke2_cni }}"
  tls-san:
    - "{{ fqdn }}"
  write-kubeconfig-mode: "0644"
```

### Agent Configuration Defaults

```yaml
rke2_agent_config:
  server: "https://{{ kube_api_host }}:9345"
```

## Dependencies

- `rke2_setup` role (recommended to run first)

## Example Playbook

```yaml
---
- name: Configure RKE2
  hosts: all
  become: true
  roles:
    - rke2_config
```

With custom CNI:

```yaml
---
- name: Configure RKE2 with Cilium
  hosts: all
  become: true
  roles:
    - role: rke2_config
      vars:
        rke2_cni: cilium
```

With custom server configuration:

```yaml
---
- name: Configure RKE2 server with custom options
  hosts: master,server
  become: true
  roles:
    - role: rke2_config
      vars:
        rke2_server_config:
          cni: "{{ rke2_cni }}"
          tls-san:
            - "{{ fqdn }}"
            - "api.example.com"
          write-kubeconfig-mode: "0644"
          disable-cloud-controller: true
          node-taint:
            - "node-role.kubernetes.io/control-plane=true:NoSchedule"
```

With disabled components:

```yaml
---
- name: Configure RKE2 without default ingress
  hosts: all
  become: true
  roles:
    - role: rke2_config
      vars:
        rke2_disable_components:
          - rke2-ingress-nginx
```

## Node Role Detection

The role automatically detects whether a node should be configured as a server or agent based on:
- `rke2_node_role` variable (typically `master` for first node)
- `node_roles` variable containing comma-separated roles (`cp`, `etcd`, `worker`)

Server configuration is used if:
- `rke2_node_role == 'master'` OR
- `'cp' in node_roles` OR
- `'etcd' in node_roles`

Otherwise, agent configuration is used.

## Configuration File Generation

The role generates `/etc/rancher/rke2/config.yaml` with:

**For server nodes:**
- CNI configuration
- TLS SANs (including FQDN)
- Kubeconfig write mode
- Server join URL (for additional servers)
- Cluster token (if joining existing cluster)
- Any disabled components
- Additional custom configuration

**For agent nodes:**
- Server join URL
- Cluster token
- Any disabled components
- Additional custom configuration

## Variables Required from Inventory

The following variables should be set in your inventory:

- `fqdn` - Fully qualified domain name for the cluster
- `kube_api_host` - IP address of the first master node
- `rke2_node_role` - Node role (`master`, `server`, or `agent`)
- `node_roles` - Comma-separated roles (`cp,etcd` or `worker`)
- `rke2_token` - Cluster join token (for non-master nodes)

Example inventory:

```yaml
all:
  vars:
    fqdn: cluster.example.com
    kube_api_host: 10.0.1.10
  children:
    master:
      hosts:
        node-1:
          rke2_node_role: master
          node_roles: cp,etcd
    server:
      hosts:
        node-2:
          rke2_node_role: server
          node_roles: cp,etcd
          rke2_token: "{{ master_token }}"
    worker:
      hosts:
        node-3:
          rke2_node_role: agent
          node_roles: worker
          rke2_token: "{{ master_token }}"
```

## Handlers

- `restart rke2` - Restarts the appropriate RKE2 service (rke2-server or rke2-agent) when configuration changes

## Testing

```bash
# Test the role syntax
ansible-playbook --syntax-check -i inventory.yml playbook.yml

# Run in check mode (dry run)
ansible-playbook --check -i inventory.yml playbook.yml

# Run the playbook
ansible-playbook -i inventory.yml playbook.yml

# Verify configuration
ansible all -i inventory.yml -m shell -a "cat /etc/rancher/rke2/config.yaml"
```

## License

Apache 2.0
