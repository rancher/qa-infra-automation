# K3s IPv6-Only Playbook

Deploys an IPv6-only K3s cluster with the same roles and node flow as
[`ansible/k3s/default`](../default/README.md): `setup` → `k3s_hardening` → `k3s_install`
on the master, then the servers and agents join. Differences from the default playbook:

- Connection settings come from the inventory, so the bastion `ProxyCommand` generated
  by `make infra-up` is honoured. The `bastion` group is never a K3s node.
- `kube_api_host`/`fqdn` come from the inventory (or `KUBE_API_HOST`/`FQDN`), not tfstate.
- IPv6 literals are bracketed in join and kubeconfig URLs.
- The system-pod health check runs on the first `cp` node, and the kubeconfig is
  also copied to `~/.kube/config` on the bastion.
- K3s IPv6 settings (`cluster-cidr`, `service-cidr`, `node-ip`) live in
  `server_flags`/`worker_flags`; see [`examples/`](./examples).

Nodes are reached over IPv6 through a dual-stack bastion. `kube_api_host` must be IPv6; an IPv4 value falls back to the master's `ansible_host_ipv6`. For dual-stack use [`ansible/k3s/dualstack`](../dualstack/README.md).

## Usage

1. Copy `tofu/aws/modules/ipv6/examples/terraform.tfvars.sample` to
   `tofu/aws/modules/ipv6/terraform.tfvars` and fill it in.
2. Copy `examples/vars.ipv6.yaml` to `ansible/k3s/ipv6/vars.yaml`.
3. Run from the repository root:

   ```bash
   make infra-up DISTRO=k3s ENV=ipv6
   make cluster  DISTRO=k3s ENV=ipv6
   make status   DISTRO=k3s ENV=ipv6
   make infra-down DISTRO=k3s ENV=ipv6
   ```

   Rancher is not deployed for this environment (`make all` runs infra-up + cluster).

Bring-your-own nodes: copy `inventory/inventory.yml.template` to `inventory/inventory.yml`
and run `ansible-playbook -i ansible/k3s/ipv6/inventory/inventory.yml ansible/k3s/ipv6/k3s-playbook-ipv6.yml`.
Each host needs `ansible_host` (the address Ansible connects to) and `ansible_host_ipv6`.

The kubeconfig is written to `ansible/k3s/ipv6/kubeconfig.yaml`.
