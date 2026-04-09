# rke2_cluster

Starts RKE2 services and orchestrates cluster formation.

## Description

This role handles the cluster formation process by starting RKE2 services in the proper sequence: master node first, then additional server nodes (control-plane/etcd), then agent nodes (workers). It manages token distribution, waits for nodes to become ready, and fetches the kubeconfig for cluster access.

## Requirements

- Ansible 2.10 or higher
- Root/sudo access on target nodes
- RKE2 already installed (via rke2_install role)
- RKE2 configuration generated (via rke2_config role)

## Role Variables

Variables defined in `defaults/main.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `rke2_wait_timeout` | `300` | Seconds to wait for RKE2 to be ready |
| `rke2_check_interval` | `10` | Seconds between status checks |
| `rke2_kubeconfig_source` | `/etc/rancher/rke2/rke2.yaml` | Path to kubeconfig on master node |
| `rke2_kubeconfig_dest` | `{{ playbook_dir }}/kubeconfig.yaml` | Local path to save kubeconfig |
| `rke2_wait_for_ready` | `true` | Wait for nodes to reach Ready state |
| `rke2_service_start_retries` | `3` | Number of retries for starting services |
| `rke2_service_start_delay` | `10` | Seconds between service start retries |

Additional variables used (defined in rke2_config role):

| Variable | Required | Description |
|----------|----------|-------------|
| `rke2_node_role` | Yes | Node role: `master`, `server`, or `agent` |
| `node_roles` | Yes | Comma-separated roles: `cp`, `etcd`, `worker` |
| `rke2_token_file` | Yes | Path to token file (default: `/var/lib/rancher/rke2/server/node-token`) |
| `rke2_config_dir` | Yes | RKE2 config directory (default: `/etc/rancher/rke2`) |

## Dependencies

Required roles must run before this role:
- `rke2_setup` - System preparation
- `rke2_config` - Configuration generation
- `rke2_install` - RKE2 binary installation

## Example Playbook

### Basic Cluster Formation

```yaml
---
- name: Form RKE2 cluster
  hosts: all
  become: true
  roles:
    - rke2_setup
    - rke2_config
    - rke2_install
    - rke2_cluster
```

### With Custom Timeouts

```yaml
---
- name: Form RKE2 cluster with extended timeouts
  hosts: all
  become: true
  roles:
    - rke2_setup
    - rke2_config
    - rke2_install
    - role: rke2_cluster
      vars:
        rke2_wait_timeout: 600
        rke2_check_interval: 15
        rke2_service_start_retries: 5
```

### Skip Readiness Checks

```yaml
---
- name: Form RKE2 cluster quickly (no wait)
  hosts: all
  become: true
  roles:
    - rke2_setup
    - rke2_config
    - rke2_install
    - role: rke2_cluster
      vars:
        rke2_wait_for_ready: false
```

## Cluster Formation Process

This role orchestrates cluster formation in the following sequence:

### 1. Master Node Initialization

**What happens:**
- Starts `rke2-server` service on the master node
- Waits for RKE2 to generate the cluster token
- Reads the token and stores it as a fact
- Waits for the master node to reach Ready state

**Services started:**
- `rke2-server` (control-plane + etcd + worker capabilities)

**Key files generated:**
- `/var/lib/rancher/rke2/server/node-token` - Cluster join token

### 2. Token Distribution

**What happens:**
- Distributes the master's cluster token to all non-master nodes
- Injects the token into each node's `/etc/rancher/rke2/config.yaml`

**Why this is needed:**
- Additional nodes need the token to join the cluster
- Token is automatically generated on first master node startup

### 3. Server Nodes Startup

**What happens:**
- Starts `rke2-server` service on nodes with `cp` or `etcd` roles
- Waits for each server node to join and reach Ready state

**Node selection:**
- Nodes with `'cp' in node_roles` (control-plane)
- Nodes with `'etcd' in node_roles` (etcd member)
- Skips nodes that are already master

**Services started:**
- `rke2-server` on each server node

### 4. Agent Nodes Startup

**What happens:**
- Starts `rke2-agent` service on worker-only nodes
- Waits for each agent node to join and reach Ready state

**Node selection:**
- Nodes with `'worker' in node_roles`
- Without `cp` or `etcd` roles (pure workers)

**Services started:**
- `rke2-agent` on each worker node

### 5. Kubeconfig Retrieval

**What happens:**
- Fetches kubeconfig from master node
- Replaces `127.0.0.1` with master's actual IP address
- Saves to local file for cluster access

**File locations:**
- Source: `/etc/rancher/rke2/rke2.yaml` (on master)
- Destination: `{{ playbook_dir }}/kubeconfig.yaml` (on Ansible controller)

### 6. Cluster Status Display

**What happens:**
- Runs `kubectl get nodes -o wide` from master
- Displays all nodes in the cluster with their status

**Verification:**
- All nodes should show `Ready` status
- Roles should be correctly assigned
- IP addresses should be correct

## Node Type Detection

The role automatically determines service type based on:

**Master node** (`rke2_node_role == 'master'`):
- First node in the cluster
- Starts first to generate token
- Runs rke2-server service

**Server nodes** (additional control-plane/etcd):
- `'cp' in node_roles.split(',')`
- `'etcd' in node_roles.split(',')`
- Runs rke2-server service
- Must wait for master to complete first

**Agent nodes** (workers):
- `'worker' in node_roles.split(',')`
- NOT `cp` or `etcd`
- Runs rke2-agent service
- Should wait for server nodes

## Readiness Checks

If `rke2_wait_for_ready: true` (default), the role:

1. **Master Node**: Waits for node to reach Ready state using:
   ```bash
   /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml \
     get node <hostname> -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
   ```

2. **Server Nodes**: Same check, delegated to master node

3. **Agent Nodes**: Same check, delegated to master node

**Retries and Delays:**
- Retries: `{{ (rke2_wait_timeout / rke2_check_interval) | int }}`
- Delay: `{{ rke2_check_interval }}` seconds
- Example: 300s timeout / 10s interval = 30 retries

**Why delegate to master?**
- Only master node has kubectl and kubeconfig at this point
- Server and agent nodes haven't fetched kubeconfig yet

## Idempotency

The role is idempotent:
- If services are already running, systemd won't restart them
- If nodes are already joined, they won't rejoin
- Token distribution is safe to run multiple times
- Kubeconfig fetch overwrites previous file

**Safe to run multiple times:**
- Service start tasks use `state: started` (not restarted)
- Token injection uses `lineinfile` with `regexp` (updates in place)
- Node ready checks are read-only

## Service Management

**Services enabled:**
- All RKE2 services are enabled to start on boot

**Services started:**
- `rke2-server` on master and server nodes
- `rke2-agent` on agent nodes

**Service dependencies:**
- Services wait for network to be online
- RKE2 handles its own container runtime

## Post-Formation

After this role completes:
- Cluster is fully formed
- All nodes are joined and (optionally) Ready
- Kubeconfig is available locally at `{{ rke2_kubeconfig_dest }}`
- You can access the cluster with:
  ```bash
  kubectl --kubeconfig ansible/rke2/default/kubeconfig.yaml get nodes
  ```

Run the `rke2_health_check` role next to verify cluster health.

## Testing

```bash
# Verify all services are running
ansible all -i inventory.yml -m shell -a "systemctl status rke2-server || systemctl status rke2-agent" -b

# Check cluster status from master
ansible master -i inventory.yml -m shell -a "/var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes" -b

# Use local kubeconfig
kubectl --kubeconfig ansible/rke2/default/kubeconfig.yaml get nodes -o wide
kubectl --kubeconfig ansible/rke2/default/kubeconfig.yaml get pods -A

# Verify token was distributed
ansible all -i inventory.yml -m shell -a "grep '^token:' /etc/rancher/rke2/config.yaml" -b
```

## Troubleshooting

**Problem:** Master service fails to start

**Solution:**
- Check logs: `journalctl -u rke2-server -xe`
- Verify config: `cat /etc/rancher/rke2/config.yaml`
- Check ports: `ss -tlnp | grep -E ':(6443|9345)'`
- Ensure no conflicting K8s installations

---

**Problem:** Token file not found

**Solution:**
- Wait longer: Increase `rke2_wait_timeout`
- Check master service: `systemctl status rke2-server`
- Verify RKE2 data directory exists: `ls -la /var/lib/rancher/rke2/server/`
- Check SELinux/AppArmor: `ausearch -m avc` or `dmesg | grep apparmor`

---

**Problem:** Server/agent nodes fail to join

**Solution:**
- Verify token in config: `grep token /etc/rancher/rke2/config.yaml`
- Check connectivity to master: `curl -k https://<master-ip>:9345/v1-rke2/readyz`
- Check firewall rules on master (port 9345)
- Verify DNS resolution: `nslookup <master-hostname>`
- Check logs: `journalctl -u rke2-server -f` or `journalctl -u rke2-agent -f`

---

**Problem:** Nodes stuck in NotReady state

**Solution:**
- Check CNI plugin: `kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get pods -n kube-system | grep canal`
- Verify networking: `ip addr` and `ip route`
- Check container runtime: `crictl ps`
- Wait longer: Some CNI plugins take 2-3 minutes
- Disable wait if stuck: `rke2_wait_for_ready: false`

---

**Problem:** Kubeconfig has wrong IP address

**Solution:**
- The role replaces 127.0.0.1 with `ansible_host`
- Verify inventory has correct IPs: `ansible-inventory -i inventory.yml --list`
- Manually edit kubeconfig if needed: `sed -i 's/OLD_IP/NEW_IP/' kubeconfig.yaml`

---

**Problem:** "Unable to connect to the server: dial tcp: lookup" error

**Solution:**
- Kubeconfig references hostname, not IP
- Edit kubeconfig: Replace `server: https://<hostname>:6443` with `server: https://<ip>:6443`
- Or ensure `/etc/hosts` has correct entry

---

**Problem:** Services start but cluster doesn't form

**Solution:**
- Verify all nodes have same RKE2 version: `rke2 --version`
- Check time synchronization: `timedatectl`
- Verify token matches on all nodes
- Check etcd health: `kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes -o wide`

## Performance Tuning

### Faster Cluster Formation

```yaml
rke2_wait_for_ready: false  # Skip readiness checks
rke2_service_start_retries: 1  # Reduce retries
```

**Trade-off:** Cluster may not be fully ready when playbook completes

### More Resilient Formation

```yaml
rke2_wait_timeout: 600  # 10 minutes
rke2_check_interval: 5  # Check more frequently
rke2_service_start_retries: 5  # More retries
rke2_service_start_delay: 15  # Longer delays
```

**Trade-off:** Slower playbook execution

### Large Clusters

For clusters with 10+ nodes:
```yaml
rke2_wait_timeout: 900  # 15 minutes
rke2_check_interval: 20  # Check less frequently
```

## Integration with Other Roles

This role integrates with:

**Previous roles:**
- `rke2_setup` - Prepares system (firewall, packages)
- `rke2_config` - Generates configuration files
- `rke2_install` - Installs RKE2 binaries

**Next role:**
- `rke2_health_check` - Validates cluster is healthy

**Typical playbook order:**
```yaml
roles:
  - rke2_setup
  - rke2_config
  - rke2_install
  - rke2_cluster      # <-- This role
  - rke2_health_check
```

## Advanced Usage

### Custom Kubeconfig Location

```yaml
- role: rke2_cluster
  vars:
    rke2_kubeconfig_dest: /tmp/my-cluster.yaml
```

### Different Token File Location

If using custom RKE2 configuration:
```yaml
- role: rke2_cluster
  vars:
    rke2_token_file: /custom/path/to/token
```

### No Readiness Checks for Fast Iteration

During development:
```yaml
- role: rke2_cluster
  vars:
    rke2_wait_for_ready: false
```

Then check manually:
```bash
watch kubectl --kubeconfig kubeconfig.yaml get nodes
```

## Security Considerations

**Token Security:**
- Token file has 0600 permissions (read by root only)
- Token is distributed via Ansible (encrypted if using vault)
- Token is written to config with 0600 permissions

**Kubeconfig Security:**
- Fetched kubeconfig contains cluster-admin credentials
- Store securely and restrict access
- Consider using RBAC and service accounts for applications

**Network Security:**
- Port 6443 (Kubernetes API) exposed on master
- Port 9345 (RKE2 supervisor) exposed on master
- Port 10250 (kubelet) exposed on all nodes

Ensure firewall rules are properly configured (via rke2_setup role).

## License

Apache 2.0
