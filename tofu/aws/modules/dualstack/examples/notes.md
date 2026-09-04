## Values to be set in terraform.tfvars for the different dualstack/ipv6 scenarios: 

1. Dualstack - ipv4+ipv6 on both nodes and bastion node. Use IPv4 for kube_api_host. 
```
enable_ipv6  = true 
enable_public_ip  = true  
kube_api_host_ipv6 = false 
```

2. Dualstack - ipv4+ipv6 on both nodes and bastion node. Use IPv6 for kube_api_host.
```
enable_ipv6  = true 
enable_public_ip  = true  
kube_api_host_ipv6 = true 
```

3. IPv6 Only scenario. Bastion node will have both ipv4 and ipv6 enabled. The rke2 cluster will have ONLY IPv6 enabled. 

```
enable_ipv6  = true 
enable_public_ip  = false  
kube_api_host_ipv6 = true 
```