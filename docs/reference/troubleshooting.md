# Troubleshooting

Common issues and solutions, organized by component.

## General

### `make validate` fails

**Symptom:** Missing prerequisites.

**Fix:** Install the missing tools, then re-run:

```bash
# Python deps
pip install -r requirements.txt

# Ansible collections
ansible-galaxy collection install -r requirements.yml
# or
make collections
```

### Inventory file not found

**Symptom:** `Error: Inventory file not found`

**Cause:** `make cluster` or `make rancher` was run before `make infra-up`.

**Fix:** Either run `make infra-up` first, or create a [manual inventory](inventory-format.md).

---

## SSH & Connectivity

### Ansible can't reach nodes (`ping` fails)

**Symptom:** `make ping` or `ansible ... -m ping` returns `UNREACHABLE`.

**Checklist:**
1. Verify the IP is reachable: `ssh <user>@<ip>`
2. Check `ansible_user` has SSH key access (or set `ansible_ssh_private_key_file`)
3. Ensure the security group / firewall allows SSH (port 22) from your IP
4. For airgap nodes, verify the bastion is reachable first

### Permission denied (publickey)

**Cause:** SSH key mismatch between what Tofu injected and what Ansible is using.

**Fix:**
- Verify `public_ssh_key` in `terraform.tfvars` matches the key pair Ansible uses
- For BYO nodes, ensure the public key is in `~/.ssh/authorized_keys` on the target

### Airgap SSH proxy issues

**Cause:** SSH ProxyCommand through the bastion fails.

**Checklist:**
1. Can you SSH to the bastion directly? `ssh -i <key> <bastion_user>@<bastion_ip>`
2. From the bastion, can you reach airgap nodes? `ssh <airgap_node_private_ip>`
3. Check `ssh_private_key_file` in group vars matches the key on disk

See also: [SSH Troubleshooting (airgap)](../../ansible/rke2/airgap/docs/knowledge_base/SSH_TROUBLESHOOTING.md)

---

## OpenTofu / Infrastructure

### `tofu init` fails

**Cause:** Network issues downloading providers, or version constraints.

**Fix:**
- Check internet connectivity
- If behind a proxy, set `HTTPS_PROXY`
- Delete `.terraform/` and retry: `rm -rf tofu/aws/modules/cluster_nodes/.terraform && make infra-init`

### `tofu apply` fails with credential errors

**Fix:**
- Check `aws_access_key` and `aws_secret_key` in `terraform.tfvars`
- Alternatively, use environment variables: `export AWS_ACCESS_KEY_ID=... AWS_SECRET_ACCESS_KEY=...`
- Verify the IAM user has permissions for EC2, VPC, and (optionally) Route53

### Resources already exist

**Cause:** Running `tofu apply` in the default workspace when a previous deployment wasn't destroyed.

**Fix:**
- Destroy first: `make infra-down`
- Or use workspaces: `cd tofu/aws/modules/cluster_nodes && tofu workspace new my-test`

---

## RKE2

### RKE2 service fails to start

**Symptom:** Ansible task hangs or fails at "start rke2-server".

**Debug:**
```bash
ssh <user>@<node_ip>
sudo journalctl -u rke2-server --no-pager -n 100
sudo systemctl status rke2-server
```

**Common causes:**
- Port conflicts: ensure 6443, 9345, 10250 are open between nodes
- Insufficient resources: RKE2 needs at least 2 vCPU, 4 GB RAM
- CNI issues: check `/var/lib/rancher/rke2/agent/logs/`

### Nodes join but show NotReady

**Cause:** Usually CNI-related — pods can't get network assigned.

**Debug:**
```bash
kubectl --kubeconfig <kubeconfig> get pods -n kube-system
kubectl --kubeconfig <kubeconfig> describe node <node-name>
```

**Fix:** Ensure the security group allows the CNI port range (e.g., VXLAN 8472/UDP for Canal, BGP 179/TCP for Calico).

### Health check fails

**Cause:** Cluster is still converging. Nodes or system pods may need more time.

**Fix:** Wait 2–3 minutes and re-run just the health check:
```bash
ansible-playbook -i <inventory> ansible/rke2/default/rke2-playbook.yml --tags health
```

### Token distribution errors

**Cause:** Master node didn't start successfully, so the token file wasn't created.

**Fix:** Check that the master node's RKE2 service is running, then re-run:
```bash
ansible-playbook -i <inventory> ansible/rke2/default/rke2-playbook.yml --tags cluster
```

---

## K3s

### K3s service fails to start

**Debug:**
```bash
ssh <user>@<node_ip>
sudo journalctl -u k3s --no-pager -n 100
```

**Common causes:**
- Port 6443 already in use
- Insufficient permissions (K3s needs root or a user with full sudo)

### Nodes not joining

**Fix:** Check that all nodes can reach the master on port 6443. Verify the join token was distributed correctly in the Ansible output.

---

## Rancher

### Rancher pods not starting

**Debug:**
```bash
kubectl --kubeconfig <kubeconfig> get pods -n cattle-system
kubectl --kubeconfig <kubeconfig> logs -n cattle-system -l app=rancher
kubectl --kubeconfig <kubeconfig> get pods -n cert-manager
```

**Common causes:**
- cert-manager not ready — wait and check `cert-manager` namespace pods
- Image pull errors — check node internet access (or registry configuration in airgap)

### Can't access Rancher UI

**Checklist:**
1. DNS: `nslookup <fqdn>` — must resolve to your cluster LB or node IP
2. Ports: 80 and 443 must be open
3. Ingress: `kubectl get ingress -n cattle-system`
4. For local testing: add `<node-ip> <fqdn>` to `/etc/hosts`

### Bootstrap password doesn't work

After the first login, Rancher switches to the permanent `password`. The `bootstrap_password` is single-use.

---

## Airgap-Specific

### Tarball download fails on bastion

**Cause:** Bastion can't reach GitHub to download RKE2 releases.

**Fix:** Verify bastion has internet: `ssh bastion && curl -I https://github.com`

### Tarball transfer fails to airgap nodes

**Cause:** Disk space or SSH connectivity.

**Fix:**
- Check bastion disk: `df -h` (need ~5 GB for tarballs)
- Check airgap node disk: `df -h` (need ~20 GB for installation)
- Test SSH: `make test-ssh ENV=airgap`

### Checksum verification failures

**Symptom:** `download sha256 does not match`

**Fix:**
```bash
ansible-playbook -i ansible/rke2/airgap/inventory/inventory.yml \
  ansible/rke2/airgap/playbooks/debug/fix-checksum-issues.yml
```

### Private registry errors

**Symptom:** `failed to pull image` after RKE2 is running.

**Debug:**
```bash
# Check registry config
ssh <bastion> -> ssh <airgap-node>
cat /etc/rancher/rke2/registries.yaml

# Test registry connectivity
curl -k https://<registry-url>/v2/

# Check containerd logs
cat /var/lib/rancher/rke2/agent/containerd/containerd.log
```

**Fix:** Re-apply registry config: `make registry ENV=airgap`

---

## Diagnostic Playbooks (Airgap)

The airgap deployment includes several diagnostic playbooks:

```bash
# Test SSH connectivity
ansible-playbook -i <inventory> ansible/rke2/airgap/playbooks/debug/test-ssh-connectivity.yml

# Fix checksum issues
ansible-playbook -i <inventory> ansible/rke2/airgap/playbooks/debug/fix-checksum-issues.yml

# Fix RKE2 config
ansible-playbook -i <inventory> ansible/rke2/airgap/playbooks/debug/fix-rke2-config.yml

# Validate upgrade readiness
ansible-playbook -i <inventory> ansible/rke2/airgap/playbooks/debug/validate-upgrade-readiness.yml
```

## Getting More Help

- Add `-v`, `-vv`, or `-vvv` to any `ansible-playbook` command for more verbose output
- Check the [FAQ](../faq.md)
- Review the component-specific READMEs in `ansible/rke2/default/README.md`, `ansible/k3s/default/README.md`, or `ansible/rke2/airgap/README.md`
