# RKE2 Airgap Upgrade Guide

This guide provides step-by-step instructions for upgrading RKE2 clusters in airgap environments using the provided Ansible playbooks.

## Overview

The RKE2 upgrade process for airgap environments involves:

1. **Pre-upgrade validation** - Check current cluster state and requirements
2. **Download new version** - Fetch RKE2 tarball bundle on bastion host
3. **Server upgrade** - Upgrade the first server node (control plane)
4. **Agent upgrade** - Upgrade worker nodes one by one
5. **Post-upgrade verification** - Validate cluster functionality

## Prerequisites

### System Requirements

- Existing RKE2 cluster deployed using the airgap installation method
- Bastion host with internet access
- All cluster nodes accessible from bastion via SSH
- Sufficient disk space (at least 5GB free on `/var/lib/rancher`)
- Root or sudo access on all nodes

### Version Compatibility

- **Supported upgrade paths**: Minor version upgrades (e.g., v1.31.1 → v1.31.11)
- **Major version upgrades**: Test thoroughly in non-production environments first
- **Downgrade**: Not supported - always backup before upgrading

## Configuration

### 1. Update Target Version

If you wish to update a specific version of RKE2 other than the latest, you can update `inventory/group_vars/all.yml` to specify the target RKE2 version:

```yaml
# RKE2 Configuration
rke2_version: "v1.31.11+rke2r1"  # Update to desired version
```

### 2. Verify Inventory

Ensure your [`inventory/inventory.yml`](../../inventory/inventory.yml.template) is correctly configured:

```yaml
all:
  children:
    bastion:
      hosts:
        bastion-host:
          ansible_host: 10.0.1.10
    airgap_nodes:
      hosts:
        rke2-server-1:
          ansible_host: 10.0.2.10
        rke2-agent-1:
          ansible_host: 10.0.2.11
        rke2-agent-2:
          ansible_host: 10.0.2.12
```

## Upgrade Process

### Step 1: Pre-upgrade Backup (Recommended)

Before starting the upgrade, create backups of critical data:

```bash
# On each cluster node, backup configuration
sudo cp -r /etc/rancher/rke2 /opt/rke2-config-backup-$(date +%Y%m%d)
sudo cp -r /var/lib/rancher/rke2/server /opt/rke2-server-backup-$(date +%Y%m%d)

# Backup etcd (on server nodes)
sudo /var/lib/rancher/rke2/bin/etcdctl snapshot save /opt/etcd-backup-$(date +%Y%m%d).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/var/lib/rancher/rke2/server/tls/etcd/server-ca.crt \
  --cert=/var/lib/rancher/rke2/server/tls/etcd/server-client.crt \
  --key=/var/lib/rancher/rke2/server/tls/etcd/server-client.key
```

### Step 2: Run the Upgrade Playbook

Execute the upgrade playbook from your control machine:

```bash
cd ansible/rke2/airgap
ansible-playbook -i inventory/inventory.yml playbooks/deploy/rke2-upgrade-playbook.yml
```

### Step 3: Monitor the Upgrade Process

The playbook will:

1. **Validate** current installation and check upgrade requirements
2. **Download** new RKE2 version on bastion host
3. **Upgrade server** node first (with automatic rollback on failure)
4. **Upgrade agents** one by one to maintain cluster availability
5. **Verify** cluster functionality and node status

## Upgrade Stages Explained

### Stage 1: Pre-upgrade Validation

- Checks if RKE2 is installed on all nodes
- Verifies current versions and service status
- Validates disk space availability
- Displays upgrade requirements

### Stage 2: Download New Version

- Downloads RKE2 tarball bundle on bastion host
- Creates new bundle with updated version
- Skips download if all nodes are already at target version

### Stage 3: Server Node Upgrade

- Stops RKE2 server service
- Backs up current configuration and binaries
- Installs new RKE2 version
- Restarts server service
- Verifies server functionality before proceeding

### Stage 4: Agent Node Upgrade (Serial)

- Upgrades one agent node at a time
- Stops agent service
- Installs new RKE2 version
- Restarts agent service
- Verifies node rejoins cluster before next agent

### Stage 5: Post-upgrade Verification

- Checks all nodes are in Ready state
- Verifies cluster functionality
- Updates kubectl on bastion host
- Displays final cluster status

## Troubleshooting

### Common Issues

#### 1. Service Fails to Start After Upgrade

```bash
# Check service status
sudo systemctl status rke2-server  # or rke2-agent

# Check logs
sudo journalctl -u rke2-server -f

# Common fixes:
# - Verify configuration file syntax
# - Check disk space
# - Restart the service
sudo systemctl restart rke2-server
```

#### 2. Node Doesn't Rejoin Cluster

```bash
# On the problematic node, check agent logs
sudo journalctl -u rke2-agent -f

# Verify network connectivity to server
telnet <server-ip> 6443

# Check node token
sudo cat /var/lib/rancher/rke2/server/node-token
```

#### 3. Upgrade Fails - Rollback Required

The playbook includes automatic rollback, but manual rollback may be needed:

```bash
# Stop current service
sudo systemctl stop rke2-server  # or rke2-agent

# Restore backup binary
sudo cp /opt/rke2-backup-*/rke2-binary-backup /usr/local/bin/rke2

# Restore configuration
sudo cp /opt/rke2-backup-*/config.yaml /etc/rancher/rke2/config.yaml

# Restart service
sudo systemctl start rke2-server  # or rke2-agent
```

### Recovery Procedures

#### Complete Cluster Recovery

If the upgrade fails catastrophically:

1. **Stop all RKE2 services** on all nodes
2. **Restore etcd backup** on server node:

   ```bash
   sudo /var/lib/rancher/rke2/bin/etcdctl snapshot restore /opt/etcd-backup-*.db \
     --data-dir /var/lib/rancher/rke2/server/db/etcd
   ```

3. **Restore configurations** from backups
4. **Restart services** starting with server node

#### Partial Recovery

If only some nodes fail:

1. **Identify failed nodes** using `kubectl get nodes`
2. **Manually fix** failed nodes using troubleshooting steps
3. **Re-run upgrade** playbook with `--limit` flag:

   ```bash
   ansible-playbook -i inventory/inventory.yml playbooks/deploy/rke2-upgrade-playbook.yml --limit failed_node
   ```

## Validation Commands

### Check Cluster Status

```bash
# From bastion host
kubectl get nodes -o wide
kubectl get pods -A
kubectl cluster-info

# Check RKE2 versions on nodes
ansible airgap_nodes -i inventory/inventory.yml -m shell -a "/usr/local/bin/rke2 --version"
```

### Verify Upgrade Success

```bash
# Check all nodes are at target version
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.nodeInfo.kubeletVersion}{"\n"}{end}'

# Verify system pods are running
kubectl get pods -n kube-system

# Check cluster health
kubectl get componentstatuses
```

## Best Practices

### Before Upgrade

- [ ] **Test in non-production** environment first
- [ ] **Create full backups** of etcd and configurations
- [ ] **Verify sufficient disk space** on all nodes
- [ ] **Check release notes** for breaking changes
- [ ] **Plan maintenance window** during low-traffic periods

### During Upgrade

- [ ] **Monitor logs** continuously during upgrade
- [ ] **Verify each stage** completes successfully before proceeding
- [ ] **Keep backup restoration commands** ready
- [ ] **Have rollback plan** prepared

### After Upgrade

- [ ] **Verify all applications** are functioning correctly
- [ ] **Update monitoring** and alerting configurations
- [ ] **Document upgrade** results and any issues encountered
- [ ] **Clean up old backups** after successful validation

## Automation and Scheduling

### Automated Upgrades

For production environments, consider:

```bash
# Create upgrade script
cat > /opt/rke2-upgrade.sh << 'EOF'
#!/bin/bash
cd /path/to/ansible/rke2/airgap
ansible-playbook -i inventory/inventory.yml playbooks/deploy/rke2-upgrade-playbook.yml
EOF

# Schedule with cron (example: monthly on first Sunday at 2 AM)
0 2 * * 0 [ $(date +\%d) -le 7 ] && /opt/rke2-upgrade.sh >> /var/log/rke2-upgrade.log 2>&1
```

### CI/CD Integration

Integrate with your CI/CD pipeline:

```yaml
# Example GitLab CI job
rke2-upgrade:
  stage: deploy
  script:
    - cd ansible/rke2/airgap
    - ansible-playbook -i inventory/inventory.yml playbooks/deploy/rke2-upgrade-playbook.yml
  when: manual
  only:
    - main
```

## Support and Resources

- **RKE2 Documentation**: <https://docs.rke2.io/>
- **Release Notes**: <https://github.com/rancher/rke2/releases>
- **Community Support**: <https://rancher.com/support/>
- **Troubleshooting**: Check logs in `/var/log/` and `journalctl`
