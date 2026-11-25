## Values to be set in terraform.tfvars for the IPv6 ONLY scenarios: 

Bastion node will have both ipv4 and ipv6 enabled. The rke2 cluster will have ONLY IPv6 enabled. 

```
enable_ipv6  = true 
enable_public_ip  = false  
kube_api_host_ipv6 = true 
# Optional: defaults to the public nat64.net resolver. Point at a VPC DNS64
# resolver instead where one is available.
# ipv6_dns64_resolvers = ["2001:db8::2"]
```
