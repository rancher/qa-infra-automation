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
| `rke2_cni` | `calico` (direct role); `""` (shared playbook when unspecified) | Explicit `""` omits the key and uses the RKE2 default (Canal) when no other CNI input is set. For compatibility, `calico` yields to a CNI in `rke2_additional_config` or `rke2_server_config`; other nonempty values take precedence. Agents never render `cni` (server-only option). |
| `rke2_server_config` | See defaults | Configuration for server nodes |
| `rke2_agent_config` | See defaults | Configuration for agent nodes |
| `rke2_disable_components` | `[]` | List of components to disable |
| `rke2_additional_config` | `{}` | Additional configuration options |

### CNI default migration

Direct role consumers retain the historical Calico default. The shared playbook
explicitly passes an empty CNI when none is requested, and the new-cluster
examples use `cni: ""` to select RKE2's default, Canal. Direct role consumers
can opt into that behavior with `rke2_cni: ""`. Existing CNI precedence remains
unchanged.

The `calico` role default is intentional: changing it would silently select
Canal on reruns for existing direct-role consumers. Only the shared playbook's
unspecified CNI and the new-cluster examples default to `""`.

Set any CNI supported by the target RKE2 version and OS explicitly as needed:
`canal`, `calico`, `cilium`, or `flannel`. Multus combinations are passed through
as comma-separated strings: `multus,canal`, `multus,calico`, `multus,cilium`, or
`multus,flannel`. Multus requires a primary CNI; see the
[RKE2 networking](https://docs.rke2.io/networking/basic_network_options) and
[Multus](https://docs.rke2.io/networking/multus_sriov) requirements.

Before rerunning against an existing Calico cluster, set `cni: calico` in
`vars.yaml`; direct consumers relying on the role default need no migration.
Preserve the CNI already installed; empty CNI is not an in-place CNI migration.
Consumers such as DTF that generate their own variables must also stop injecting
Calico if they want the RKE2 default; changing this role cannot override an
explicit caller choice.

### Server Configuration Defaults

```yaml
# cni is rendered separately from rke2_cni when set (empty = RKE2 default)
rke2_server_config:
  tls-san:
    - "{{ fqdn }}"
  write-kubeconfig-mode: "0644"
```

Keep kubeconfig modes quoted, including in `server_flags` or
`rke2_additional_config`. The template preserves strings so `"0644"` is not
decoded as the YAML integer `420` and then interpreted as octal `0420` by RKE2.
This setting controls `/etc/rancher/rke2/rke2.yaml`, not the secret-bearing
`config.yaml`, which remains `0600`. The admin kubeconfig is readable by local
users at `0644`; use a stricter mode on shared hosts. RKE2 must reload the corrected
configuration to repair an existing kubeconfig. Before writing configuration,
the role discovers the existing service, so a changed configuration restarts
running nodes at the end of the configuration play, before `rke2_install`
runs. Fresh nodes and stopped services are left for the normal cluster-start
phase, which reads the corrected configuration. An explicit `rke2_installed: false` still
suppresses the handler; those callers must apply the configuration themselves.
Reruns preserve an existing join token unless a token is explicitly supplied,
allowing secondary servers and agents to restart before cluster formation.
Existing configuration read for token preservation must be a YAML mapping;
an empty file or YAML null is treated as an empty configuration. Invalid YAML
or another value type stops the role with a clear error before overwriting the
configuration or restarting RKE2, without logging its contents. Repair the
existing file before rerunning. Explicit token overrides skip reading the old
configuration. Join tokens are quoted to preserve their exact string values.

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
        rke2_cni: cilium
        rke2_server_config:
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
- `node_type` variable (typically `master` for first node)
- `node_roles` variable as a YAML list (e.g., `['cp', 'etcd', 'worker']`)

Server configuration is used if:
- `node_type == 'master'` OR
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
- `node_type` - Node role (`master`, `server`, or `agent`)
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
          node_type: master
          node_roles: cp,etcd
    server:
      hosts:
        node-2:
          node_type: server
          node_roles: cp,etcd
          rke2_token: "{{ master_token }}"
    worker:
      hosts:
        node-3:
          node_type: agent
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
