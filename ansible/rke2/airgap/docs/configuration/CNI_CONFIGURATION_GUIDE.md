# RKE2 CNI Configuration Guide

This guide explains how to configure different Container Network Interface (CNI) plugins for your RKE2 airgap cluster.

## Overview

RKE2 supports multiple CNI plugins, each with different capabilities and use cases. The airgap deployment system allows you to easily switch between CNI plugins by modifying the configuration in [`inventory/group_vars/all.yml`](../../inventory/group_vars/all.yml.template).

## Available CNI Options

### 1. Canal (Default)
**Best for**: Most deployments, balanced features and performance

Canal combines Flannel for networking and Calico for network policies, providing a good balance of features and simplicity.

```yaml
# inventory/group_vars/all.yml
cni_plugin: "canal"

cni_config:
  canal:
    # Flannel backend options: vxlan, host-gw, udp
    flannel_backend: "vxlan"  # Default: vxlan
    # Enable Calico network policies
    network_policy: true
```

**Features:**
- ✅ Network policies (via Calico)
- ✅ Simple configuration
- ✅ Good performance
- ✅ Wide compatibility
- ❌ Limited advanced features

### 2. Calico
**Best for**: Advanced networking, strict network policies, BGP routing

Pure Calico CNI provides advanced networking features and excellent network policy support.

```yaml
# inventory/group_vars/all.yml
cni_plugin: "calico"

cni_config:
  calico:
    # IP-in-IP encapsulation: Always, CrossSubnet, Never
    ipip_mode: "Always"
    # Enable BGP routing
    bgp_enabled: true
    # Network policy enforcement
    network_policy: true
```

**Features:**
- ✅ Advanced network policies
- ✅ BGP routing support
- ✅ IP-in-IP encapsulation
- ✅ High performance
- ✅ Enterprise features
- ❌ More complex configuration

### 3. Cilium
**Best for**: Advanced security, observability, service mesh features

Cilium provides eBPF-based networking with advanced security and observability features.

```yaml
# inventory/group_vars/all.yml
cni_plugin: "cilium"

cni_config:
  cilium:
    # Enable Hubble for network observability
    hubble_enabled: true
    # Network policy enforcement
    network_policy: true
    # BGP support
    bgp_enabled: false
    # Service mesh capabilities
    service_mesh: false
```

**Features:**
- ✅ eBPF-based networking
- ✅ Advanced security policies
- ✅ Network observability (Hubble)
- ✅ Service mesh capabilities
- ✅ High performance
- ❌ Requires newer kernels
- ❌ More resource intensive

### 4. Multus
**Best for**: Multiple network interfaces, SR-IOV, complex networking

Multus enables multiple network interfaces per pod, useful for complex networking scenarios.

```yaml
# inventory/group_vars/all.yml
cni_plugin: "multus"

cni_config:
  multus:
    # Primary CNI to use with Multus
    default_cni: "canal"  # Options: canal, calico, cilium
    # Enable SR-IOV support
    sriov_enabled: false
```

**Features:**
- ✅ Multiple network interfaces per pod
- ✅ SR-IOV support
- ✅ Complex networking scenarios
- ✅ Works with other CNIs
- ❌ Increased complexity
- ❌ Requires additional configuration

### 5. None (Bring Your Own CNI)
**Best for**: Custom CNI solutions, specific requirements

Disables RKE2's built-in CNI installation, allowing you to install your own.

```yaml
# inventory/group_vars/all.yml
cni_plugin: "none"
```

**Use cases:**
- Custom CNI implementations
- Third-party CNI solutions
- Specific enterprise requirements

## Configuration Examples

### Example 1: High-Performance Calico Setup
```yaml
# inventory/group_vars/all.yml
cni_plugin: "calico"
cluster_cidr: "10.42.0.0/16"
service_cidr: "10.43.0.0/16"

cni_config:
  calico:
    # Use host-gw for better performance in same subnet
    ipip_mode: "Never"
    # Enable BGP for routing
    bgp_enabled: true
    # Strict network policies
    network_policy: true
```

### Example 2: Cilium with Observability
```yaml
# inventory/group_vars/all.yml
cni_plugin: "cilium"
cluster_cidr: "10.42.0.0/16"
service_cidr: "10.43.0.0/16"

cni_config:
  cilium:
    # Enable Hubble for network observability
    hubble_enabled: true
    # Enable network policies
    network_policy: true
    # Disable BGP (use overlay networking)
    bgp_enabled: false
```

### Example 3: Multus with Canal Backend
```yaml
# inventory/group_vars/all.yml
cni_plugin: "multus"
cluster_cidr: "10.42.0.0/16"
service_cidr: "10.43.0.0/16"

cni_config:
  multus:
    # Use Canal as the default CNI
    default_cni: "canal"
    # Enable SR-IOV for high-performance networking
    sriov_enabled: true
```

## Network Policy Examples

### Basic Network Policy (Works with Canal, Calico, Cilium)
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

### Calico-Specific Global Network Policy
```yaml
apiVersion: projectcalico.org/v3
kind: GlobalNetworkPolicy
metadata:
  name: deny-all-non-system
spec:
  selector: projectcalico.org/namespace != "kube-system"
  types:
  - Ingress
  - Egress
```

## Troubleshooting

### Common Issues

#### 1. CNI Plugin Not Starting
```bash
# Check RKE2 logs
sudo journalctl -u rke2-server -f

# Check CNI configuration
sudo ls -la /etc/cni/net.d/
sudo cat /etc/cni/net.d/*
```

#### 2. Network Connectivity Issues
```bash
# Test pod-to-pod connectivity
kubectl run test-pod --image=busybox --rm -it -- sh

# Check CNI plugin status
kubectl get pods -n kube-system | grep -E "(canal|calico|cilium)"
```

#### 3. Network Policies Not Working
```bash
# Verify network policy controller is running
kubectl get pods -n kube-system | grep -E "(calico|cilium)-node"

# Check network policy configuration
kubectl get networkpolicies -A
kubectl describe networkpolicy <policy-name> -n <namespace>
```

### Validation Commands

#### Canal/Calico Validation
```bash
# Check Calico node status
kubectl exec -n kube-system calico-node-xxx -- calicoctl node status

# Verify network policies
kubectl exec -n kube-system calico-node-xxx -- calicoctl get networkpolicies
```

#### Cilium Validation
```bash
# Check Cilium status
kubectl exec -n kube-system cilium-xxx -- cilium status

# Verify connectivity
kubectl exec -n kube-system cilium-xxx -- cilium connectivity test
```

#### Multus Validation
```bash
# Check Multus configuration
kubectl get network-attachment-definitions -A

# Verify pod with multiple interfaces
kubectl describe pod <pod-name> | grep -A 10 "Annotations"
```

## Performance Considerations

### CNI Performance Comparison

| CNI Plugin | Throughput | Latency | CPU Usage | Memory Usage | Features |
|------------|------------|---------|-----------|--------------|----------|
| Canal      | Good       | Low     | Low       | Low          | Balanced |
| Calico     | Excellent  | Very Low| Low       | Low          | Advanced |
| Cilium     | Excellent  | Low     | Medium    | Medium       | Premium  |
| Multus     | Variable*  | Variable*| Medium   | Medium       | Flexible |

*Depends on underlying CNI

### Optimization Tips

1. **For High Throughput**: Use Calico with `ipip_mode: "Never"` and BGP
2. **For Low Latency**: Use Canal with `flannel_backend: "host-gw"`
3. **For Observability**: Use Cilium with Hubble enabled
4. **For Complex Networking**: Use Multus with appropriate backend CNI

## Migration Between CNI Plugins

⚠️ **Warning**: Changing CNI plugins requires cluster recreation in most cases.

### Safe Migration Process

1. **Backup cluster data**
2. **Document current network policies**
3. **Plan downtime window**
4. **Update configuration**
5. **Recreate cluster**
6. **Restore applications**
7. **Recreate network policies**

### Migration Example
```bash
# 1. Backup current configuration
kubectl get networkpolicies -A -o yaml > network-policies-backup.yaml

# 2. Update inventory/group_vars/all.yml with new CNI
# 3. Run upgrade playbook (will recreate cluster)
ansible-playbook -i inventory/inventory.yml playbooks/deploy/rke2-upgrade-playbook.yml

# 4. Restore network policies
kubectl apply -f network-policies-backup.yaml
```

## Best Practices

### General Recommendations

1. **Start with Canal**: Good default choice for most deployments
2. **Use Calico for**: Advanced networking requirements
3. **Use Cilium for**: Security and observability focus
4. **Use Multus for**: Multiple network interface requirements
5. **Test thoroughly**: Always test CNI changes in non-production first

### Security Best Practices

1. **Enable Network Policies**: Always enable network policy enforcement
2. **Default Deny**: Start with default deny policies
3. **Least Privilege**: Only allow necessary network traffic
4. **Monitor Traffic**: Use observability tools when available
5. **Regular Updates**: Keep CNI plugins updated

### Monitoring and Observability

#### Canal/Calico Monitoring
```bash
# Monitor Calico metrics
kubectl port-forward -n kube-system calico-node-xxx 9091:9091
curl http://localhost:9091/metrics
```

#### Cilium Monitoring
```bash
# Access Hubble UI (if enabled)
kubectl port-forward -n kube-system svc/hubble-ui 12000:80

# Cilium metrics
kubectl port-forward -n kube-system cilium-xxx 9090:9090
curl http://localhost:9090/metrics
```

## Support and Resources

- **RKE2 CNI Documentation**: https://docs.rke2.io/networking
- **Calico Documentation**: https://docs.projectcalico.org/
- **Cilium Documentation**: https://docs.cilium.io/
- **Multus Documentation**: https://github.com/k8snetworkplumbingwg/multus-cni
- **Kubernetes Network Policies**: https://kubernetes.io/docs/concepts/services-networking/network-policies/

Always check the official RKE2 documentation for the latest compatibility information.