# K3s Dual-Stack (IPv4 + IPv6) Playbook

Deploys a dual-stack K3s cluster with the same roles and node flow as
[`ansible/k3s/default`](../default/README.md): `setup` → `k3s_hardening` → `k3s_install`
on the master, then the servers and agents join. Differences from the default playbook:

- Connection settings come from the inventory, so the bastion `ProxyCommand` generated
  by `make infra-up` is honoured. The `bastion` group is never a K3s node.
- `kube_api_host`/`fqdn` come from the inventory (or `KUBE_API_HOST`/`FQDN`), not tfstate.
- IPv6 literals are bracketed in join and kubeconfig URLs.
- The system-pod health check runs on the first `cp` node, and the kubeconfig is
  also copied to `~/.kube/config` on the bastion.
- K3s dual-stack settings (`cluster-cidr`, `service-cidr`, `node-ip`) live in
  `server_flags`/`worker_flags`; see [`examples/`](./examples).

For an IPv6-only cluster use [`ansible/k3s/ipv6`](../ipv6/README.md).

## Usage

1. Copy `tofu/aws/modules/dualstack/examples/terraform.tfvars.sample` to
   `tofu/aws/modules/dualstack/terraform.tfvars` and fill it in.
2. Copy a vars file to `ansible/k3s/dualstack/vars.yaml`:

   | Scenario | Source |
   |----------|--------|
   | IPv4 first | `examples/vars.dualstack.yaml` |
   | IPv6 first | `examples/vars.dualstack.ipv6.yaml` |

3. Run from the repository root:

   ```bash
   make infra-up DISTRO=k3s ENV=dualstack
   make cluster  DISTRO=k3s ENV=dualstack
   make status   DISTRO=k3s ENV=dualstack
   make infra-down DISTRO=k3s ENV=dualstack
   ```

   Rancher is not deployed for this environment (`make all` runs infra-up + cluster).

Bring-your-own nodes: copy `inventory/inventory.yml.template` to `inventory/inventory.yml`
and run `ansible-playbook -i ansible/k3s/dualstack/inventory/inventory.yml ansible/k3s/dualstack/k3s-playbook-dualstack.yml`.
Each host needs `ansible_host` (the address Ansible connects to) and `ansible_host_ipv6`.

The kubeconfig is written to `ansible/k3s/dualstack/kubeconfig.yaml`.
