# rke2_health_check

Validates RKE2 cluster health after formation.

## Description

This role performs comprehensive health checks on a deployed RKE2 cluster to verify that all components are functioning correctly. It checks the API server, node status, system pods, and etcd health. The role can be configured to either fail the playbook on errors or report warnings only, making it suitable for both deployment validation and ongoing health monitoring.

## Requirements

- Ansible 2.10 or higher
- RKE2 cluster already formed (via rke2_cluster role)
- `kubectl` available on the **Ansible control node** (localhost) — the role runs on `localhost`, not on cluster nodes
- Kubeconfig fetched locally (default: `{{ playbook_dir }}/kubeconfig.yaml`, written by the `rke2_cluster` role)

## Role Variables

Variables defined in `defaults/main.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `rke2_kubeconfig_path` | `{{ playbook_dir }}/kubeconfig.yaml` | Path to kubeconfig on the control node |
| `rke2_check_nodes_ready` | `true` | Check if all nodes are Ready |
| `rke2_check_system_pods` | `true` | Check if all system pods are Running |
| `rke2_check_api_server` | `true` | Check if API server is responsive |
| `rke2_check_etcd_health` | `true` | Check etcd cluster health |
| `rke2_health_check_timeout` | `300` | Timeout for node-ready wait (seconds); retries = timeout / retry_delay |
| `rke2_health_check_retry_delay` | `10` | Delay between retries (seconds) |
| `rke2_health_check_fail_on_error` | `true` | Whether to fail playbook if health checks fail |
| `rke2_expected_node_count` | `0` | Minimum number of expected nodes (0 = don't check) |
| `rke2_system_namespaces` | `[kube-system, kube-public, kube-node-lease]` | System namespaces to check for pod health |

Additional variables used (defined in rke2_config role):

| Variable | Required | Description |
|----------|----------|-------------|
| `rke2_node_role` | Yes | Node role: `master`, `server`, or `agent` |
| `node_roles` | Yes | Comma-separated roles: `cp`, `etcd`, `worker` |

## Dependencies

Required roles must run before this role:
- `rke2_setup` - System preparation
- `rke2_config` - Configuration generation
- `rke2_install` - RKE2 binary installation
- `rke2_cluster` - Cluster formation

## Example Playbook

### Basic Health Check

```yaml
---
# ... cluster deployment plays (rke2_setup, rke2_config, rke2_install, rke2_cluster) ...

# Health check runs on the control node using the local kubeconfig
- name: Validate RKE2 cluster health
  hosts: localhost
  connection: local
  gather_facts: false
  roles:
    - role: rke2_health_check
      vars:
        rke2_kubeconfig_path: "{{ playbook_dir }}/kubeconfig.yaml"
```

### Custom Health Checks

```yaml
---
- name: Validate RKE2 cluster health with custom settings
  hosts: localhost
  connection: local
  gather_facts: false
  roles:
    - role: rke2_health_check
      vars:
        rke2_kubeconfig_path: "{{ playbook_dir }}/kubeconfig.yaml"
        rke2_expected_node_count: 5
        rke2_health_check_fail_on_error: false  # Warnings only
        rke2_check_etcd_health: true
```

### Skip Specific Checks

```yaml
---
- name: Basic health check (skip etcd)
  hosts: localhost
  connection: local
  gather_facts: false
  roles:
    - role: rke2_health_check
      vars:
        rke2_kubeconfig_path: "{{ playbook_dir }}/kubeconfig.yaml"
        rke2_check_etcd_health: false  # Skip etcd check
        rke2_check_system_pods: false  # Skip pod check
```

## Health Check Details

### 1. API Server Health Check

**What it checks:**
- API server is responsive
- kubectl can communicate with the cluster
- API returns version information

**How it works:**
```bash
# Runs on the Ansible control node (localhost)
kubectl --kubeconfig ./kubeconfig.yaml cluster-info
kubectl --kubeconfig ./kubeconfig.yaml version -o json
```

**Success criteria:**
- Command exits with code 0
- Version information is returned

**Failure indicators:**
- Connection refused
- Timeout
- Authentication errors

---

### 2. Node Health Check

**What it checks:**
- All nodes are in Ready state
- Node count meets minimum requirement (if configured)
- No nodes in NotReady, Unknown, or SchedulingDisabled state

**How it works:**
```bash
# Get all nodes as JSON
kubectl get nodes -o json

# Parse JSON to count Ready nodes
# Check: status.conditions[?type=="Ready"].status == "True"
```

**Success criteria:**
- All nodes show Ready status
- Total nodes >= `rke2_expected_node_count` (if set)

**Failure indicators:**
- One or more nodes NotReady
- Fewer nodes than expected
- Nodes stuck in Unknown state

---

### 3. System Pods Health Check

**What it checks:**
- All system pods are Running
- No pods in Failed or CrashLoopBackOff state
- Pods in critical namespaces are healthy

**Namespaces checked:**
- `kube-system` - Core Kubernetes components
- `kube-public` - Public cluster information
- `kube-node-lease` - Node heartbeat system

**How it works:**
```bash
# Get pods in each system namespace
kubectl get pods -n kube-system -o json
kubectl get pods -n kube-public -o json
kubectl get pods -n kube-node-lease -o json

# Parse JSON to count pods by phase
# Phases: Running, Pending, Failed, Succeeded, Unknown
```

**Success criteria:**
- All pods in Running state (or Succeeded for jobs)
- No Failed pods
- Minimal Pending pods (transient state acceptable)

**Failure indicators:**
- Pods in Failed state
- Pods stuck in Pending
- CrashLoopBackOff pods
- ImagePullBackOff errors

---

### 4. etcd Health Check

**What it checks:**
- etcd cluster is healthy
- All etcd members are reachable
- etcd endpoints are responding

**Runs on:**
- Master node
- Server nodes with `etcd` role

**How it works:**
```bash
# Execute etcdctl inside etcd pod
kubectl exec -n kube-system etcd-<hostname> -- \
  etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/rke2/server/tls/etcd/server-client.crt \
  --key=/var/lib/rancher/rke2/server/tls/etcd/server-client.key \
  endpoint health -w table
```

**Success criteria:**
- All etcd endpoints healthy
- Response time < 100ms (typical)
- No connection errors

**Failure indicators:**
- etcd member unreachable
- Slow response times
- Connection timeouts
- Certificate errors

---

## Health Check Output

### Successful Health Check

```
TASK [rke2_health_check : Display health check summary]
ok: [master-node] => {
    "msg": [
        "=== RKE2 Cluster Health Check Summary ===",
        "API Server: Healthy",
        "Nodes: 5/5 Ready",
        "System Pods: 0 Failed, 0 Pending",
        "etcd: Healthy",
        "========================================"
    ]
}

TASK [rke2_health_check : Display health check complete]
ok: [master-node] => {
    "msg": "RKE2 cluster health checks complete - All systems operational!"
}
```

### Failed Health Check

```
TASK [rke2_health_check : Display health check summary]
ok: [master-node] => {
    "msg": [
        "=== RKE2 Cluster Health Check Summary ===",
        "API Server: Healthy",
        "Nodes: 3/5 Ready",
        "System Pods: 2 Failed, 1 Pending",
        "etcd: Healthy",
        "========================================"
    ]
}

TASK [rke2_health_check : Display health check warnings]
ok: [master-node] => {
    "msg": "RKE2 cluster health checks complete - Some issues detected (see above)"
}

TASK [rke2_health_check : Fail if not all nodes are Ready]
fatal: [master-node]: FAILED! => {
    "msg": "Not all nodes are Ready: 3/5"
}
```

## Idempotency

The role is fully idempotent and safe to run multiple times:
- All checks are read-only operations
- No cluster state is modified
- Can be run repeatedly for monitoring

**Safe to run:**
- After cluster formation
- As a health monitoring check
- Before and after upgrades
- As part of CI/CD pipeline validation

## Error Handling

### Fail vs Warn Mode

**Fail Mode** (`rke2_health_check_fail_on_error: true`):
- Playbook stops on first critical error
- Best for deployment validation
- Ensures cluster is fully healthy before proceeding

**Warn Mode** (`rke2_health_check_fail_on_error: false`):
- Displays warnings but continues
- Best for ongoing monitoring
- Allows manual investigation of issues

### Skip Failed Checks

To skip a check that's consistently failing:

```yaml
- role: rke2_health_check
  vars:
    rke2_check_etcd_health: false  # Skip if etcd check fails
```

## Testing

### Manual Health Verification

```bash
# Run from the Ansible control node (localhost), using the local kubeconfig
KUBECONFIG=./kubeconfig.yaml

# Verify API server
kubectl --kubeconfig "$KUBECONFIG" version

# Check nodes
kubectl --kubeconfig "$KUBECONFIG" get nodes -o wide

# Check system pods
kubectl --kubeconfig "$KUBECONFIG" get pods -A

# Check etcd health (via kubectl exec into the etcd pod on a master node)
MASTER_NODE=$(kubectl --kubeconfig "$KUBECONFIG" get nodes -l node-role.kubernetes.io/etcd=true -o name | head -1 | cut -d/ -f2)
kubectl --kubeconfig "$KUBECONFIG" \
  exec -n kube-system etcd-"${MASTER_NODE}" -- \
  etcdctl --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/rke2/server/tls/etcd/server-client.crt \
  --key=/var/lib/rancher/rke2/server/tls/etcd/server-client.key \
  endpoint health -w table
```

### Run Health Check Only

```bash
# Run only the health check role
ansible-playbook -i inventory.yml \
  --tags rke2_health_check \
  rke2-playbook.yml
```

## Troubleshooting

**Problem:** API server check fails with "connection refused"

**Solution:**
- Verify rke2-server service is running: `systemctl status rke2-server`
- Check API server logs: `journalctl -u rke2-server -xe`
- Verify port 6443 is listening: `ss -tlnp | grep 6443`
- Check firewall rules allow port 6443

---

**Problem:** Nodes stuck in NotReady state

**Solution:**
- Check node logs: `journalctl -u rke2-server -f` or `journalctl -u rke2-agent -f`
- Verify CNI plugin: `kubectl get pods -n kube-system | grep canal`
- Check kubelet logs on NotReady node
- Verify networking: `ip addr` and `ip route`
- Wait 2-3 minutes (CNI initialization can be slow)

---

**Problem:** System pods in CrashLoopBackOff

**Solution:**
- Check pod logs: `kubectl logs -n kube-system <pod-name>`
- Describe pod: `kubectl describe pod -n kube-system <pod-name>`
- Check for resource constraints: `kubectl top nodes`
- Verify image pull: `crictl images`
- Check for configuration errors in pod spec

---

**Problem:** etcd health check fails

**Solution:**
- Verify etcd pods are running: `kubectl get pods -n kube-system | grep etcd`
- Check etcd logs: `kubectl logs -n kube-system etcd-<hostname>`
- Verify TLS certificates exist:
  ```bash
  ls -la /var/lib/rancher/rke2/server/tls/etcd/
  ```
- Check etcd member list:
  ```bash
  kubectl exec -n kube-system etcd-<hostname> -- \
    etcdctl member list -w table
  ```
- Verify time synchronization: `timedatectl` (etcd requires accurate time)

---

**Problem:** "Insufficient balance" or pod count warnings

**Solution:**
- This is informational, not an error
- Check expected node count setting: `rke2_expected_node_count`
- Verify all nodes have joined: `kubectl get nodes`
- Wait for nodes to complete startup (may take 5-10 minutes)

---

**Problem:** Health check times out

**Solution:**
- Increase timeout: `rke2_health_check_timeout: 120`
- Check cluster performance: `kubectl top nodes`
- Verify network connectivity between nodes
- Check for resource contention (CPU/memory/disk)

---

**Problem:** Permission denied errors

**Solution:**
- Role must run with `become: true`
- Verify user has sudo access
- Check kubeconfig permissions: `ls -la /etc/rancher/rke2/rke2.yaml`
- Verify kubectl permissions: `ls -la /var/lib/rancher/rke2/bin/kubectl`

## Integration with Other Roles

This role integrates with:

**Previous roles:**
- `rke2_setup` - Prepares system
- `rke2_config` - Generates configuration
- `rke2_install` - Installs RKE2
- `rke2_cluster` - Forms cluster

**Next steps:**
- Deploy workloads
- Install monitoring (Prometheus, Grafana)
- Install logging (Loki, Elasticsearch)
- Deploy ingress controllers
- Install service mesh

**Typical playbook order:**
```yaml
roles:
  - rke2_setup
  - rke2_config
  - rke2_install
  - rke2_cluster
  - rke2_health_check  # <-- This role
  # Application deployment roles follow
```

## Advanced Usage

### Custom Health Check Thresholds

```yaml
- role: rke2_health_check
  vars:
    rke2_expected_node_count: 10  # Expect at least 10 nodes
    rke2_system_namespaces:
      - kube-system
      - kube-public
      - kube-node-lease
      - monitoring  # Also check monitoring namespace
      - ingress-nginx  # Also check ingress
```

### Health Check in CI/CD

```yaml
# Run health check without failing on errors
- role: rke2_health_check
  vars:
    rke2_health_check_fail_on_error: false
  register: health_check_result

# Custom failure logic
- name: Fail if critical issues found
  ansible.builtin.fail:
    msg: "Critical health issues detected"
  when:
    - health_check_result.api_version.rc != 0 or
      health_check_result.total_failed | int > 5
```

### Scheduled Health Monitoring

```yaml
# Add to cron for periodic health checks
- name: Schedule health check
  ansible.builtin.cron:
    name: "RKE2 health check"
    minute: "*/15"  # Every 15 minutes
    job: "ansible-playbook -i /path/to/inventory /path/to/health-check.yml"
```

## Performance Considerations

**Execution Time:**
- API server check: ~1-2 seconds
- Node check: ~2-5 seconds
- System pods check: ~5-10 seconds (depends on pod count)
- etcd health check: ~2-5 seconds
- **Total: ~10-20 seconds** for typical cluster

**Resource Usage:**
- Minimal CPU/memory impact
- All checks are read-only
- No cluster state modifications
- Safe to run frequently

**Optimization:**
- Disable checks you don't need
- Increase timeout for large clusters
- Run less frequently if resource-constrained

## Security Considerations

**Kubeconfig Access:**
- Health check requires a cluster-admin kubeconfig on the Ansible control node
- Default path: `{{ playbook_dir }}/kubeconfig.yaml` (fetched by the `rke2_cluster` role)
- Restrict file permissions to the user running Ansible (`chmod 600 kubeconfig.yaml`)

**etcd TLS Certificates:**
- Health check uses etcd client certificates
- Certificates are stored securely in `/var/lib/rancher/rke2/server/tls/etcd/`
- Only root can access certificate files

**Network Security:**
- Health checks only use local kubectl commands
- No external network access required
- All communication via localhost or secure cluster network

## Common Health Check Scenarios

### Scenario 1: New Cluster Deployment
```yaml
vars:
  rke2_health_check_fail_on_error: true  # Strict validation
  rke2_expected_node_count: 5
  rke2_check_etcd_health: true  # Verify etcd
```

### Scenario 2: Ongoing Monitoring
```yaml
vars:
  rke2_health_check_fail_on_error: false  # Warnings only
  rke2_check_system_pods: true
  rke2_check_nodes_ready: true
```

### Scenario 3: Fast Validation (Skip etcd)
```yaml
vars:
  rke2_health_check_fail_on_error: true
  rke2_check_etcd_health: false  # Skip slow check
  rke2_health_check_timeout: 30  # Shorter timeout
```

### Scenario 4: Production Pre-Deployment
```yaml
vars:
  rke2_health_check_fail_on_error: true  # Block if unhealthy
  rke2_expected_node_count: 10  # Verify full capacity
  rke2_check_system_pods: true  # Verify all components
  rke2_check_etcd_health: true  # Verify data layer
```

## Author

SUSE Rancher QA Team (@rancher/qa-pit-crew)

## License

Apache 2.0
