# Harvester

Ansible playbooks for operating Harvester itself and for provisioning VMs on
Harvester as Ansible-managed Kubernetes/Rancher nodes.

## Playbooks

| Playbook | Purpose |
|----------|---------|
| `upgrade-harvester.yml` | Upgrade a running Harvester cluster and restart VMs afterward. |
| `create-vms-playbook.yml` | Generate a static Ansible inventory from the `cluster_nodes_json` output of the `tofu/harvester/modules/vm` OpenTofu module. Does **not** run tofu itself — apply the module first. |
| `harvester-rancher-playbook.yml` | End-to-end: provision Harvester VMs → install RKE2 → deploy Rancher, chaining unmodified existing playbooks. |
| `import-downstream-playbook.yml` | Register an already-provisioned RKE2/K3s cluster as a downstream cluster in an existing Rancher instance. |
| `harvester-downstream-playbook.yml` | End-to-end: provision a new set of Harvester VMs → install RKE2 → import that cluster as downstream into an existing Rancher instance. |

## Provisioning VMs and installing Rancher

`harvester-rancher-playbook.yml` reuses three existing pieces of automation
end-to-end, without modifying any of them:

```text
tofu/harvester/modules/vm                   tofu init / apply (VMs, SSH key, cloud-init)
  -> tofu output -raw cluster_nodes_json > /tmp/harvester-vms/harvester-nodes.json

create-vms-playbook.yml                     (this directory)
  -> scripts/generate_inventory.py          writes ansible/rke2/default/inventory/inventory.yml
                                             (same contract/location used for AWS/GCP)

ansible/rke2/default/rke2-playbook.yml      installs and forms the RKE2 cluster
                                             (kube_api_host/fqdn come from the
                                             inventory's `all.vars`, same as any
                                             other provider — no changes needed)

ansible/rancher/default-ha/rancher-playbook.yml   deploys Rancher via Helm
                                             (kubeconfig_file/fqdn defaults
                                             already match what the RKE2 step
                                             produces)
```

Ansible never invokes `tofu` directly — infrastructure provisioning and
configuration management stay cleanly separated, the same way every other
provider in this repo works. Run tofu yourself (or via the pipeline/CI script
that wraps this workflow) before `create-vms-playbook.yml`.

### Prerequisites

In addition to the [general ansible prereqs](../README.md):

* Harvester's kubeconfig downloaded as `tofu/harvester/local.yaml` (see
  [tofu/harvester/modules/vm/README.md](../../tofu/harvester/modules/vm/README.md)).
* A `terraform.tfvars` file for `tofu/harvester/modules/vm` (nodes, ssh_key, ...).
* The module already applied, with its `cluster_nodes_json` output dumped to
  the path `create-vms-playbook.yml` expects (`/tmp/harvester-vms/harvester-nodes.json`
  by default, override with `harvester_cluster_nodes_json_file`):

  ```bash
  cd tofu/harvester/modules/vm
  tofu init
  tofu apply -var-file=terraform.tfvars -auto-approve
  mkdir -p /tmp/harvester-vms
  tofu output -raw cluster_nodes_json > /tmp/harvester-vms/harvester-nodes.json
  ```

* `vars.yaml` files for each stage, copied from their `.example`:
  * `ansible/harvester/vars.yaml` (this directory — `distro`, optional path overrides)
  * `ansible/rke2/default/vars.yaml` (RKE2 install settings)
  * `ansible/rancher/default-ha/vars.yaml` (Rancher chart/version settings)

### Running the full pipeline

```bash
cp ansible/harvester/vars.yaml.example ansible/harvester/vars.yaml
# edit ansible/harvester/vars.yaml, ansible/rke2/default/vars.yaml,
# ansible/rancher/default-ha/vars.yaml as needed

# 1. Provision the VMs with tofu (see Prerequisites above)
cd tofu/harvester/modules/vm
tofu init
tofu apply -var-file=terraform.tfvars -auto-approve
mkdir -p /tmp/harvester-vms
tofu output -raw cluster_nodes_json > /tmp/harvester-vms/harvester-nodes.json
cd -

# 2. Generate the inventory, install RKE2, deploy Rancher
ansible-playbook ansible/harvester/harvester-rancher-playbook.yml
```

### Running steps individually

```bash
# 1. Provision VMs with tofu, then dump cluster_nodes_json (see Prerequisites above)
cd tofu/harvester/modules/vm
tofu init
tofu apply -var-file=terraform.tfvars -auto-approve
mkdir -p /tmp/harvester-vms
tofu output -raw cluster_nodes_json > /tmp/harvester-vms/harvester-nodes.json
cd -

# 2. Generate the inventory from cluster_nodes_json
ansible-playbook ansible/harvester/create-vms-playbook.yml

# 3. Install RKE2 (reuses the same playbook as every other provider)
ansible-playbook -i ansible/rke2/default/inventory/inventory.yml \
  ansible/rke2/default/rke2-playbook.yml

# 4. Deploy Rancher (reuses the same playbook as every other provider)
ansible-playbook -i ansible/rke2/default/inventory/inventory.yml \
  ansible/rancher/default-ha/rancher-playbook.yml
```

### K3s instead of RKE2

Set `distro: k3s` in `ansible/harvester/vars.yaml` before running
`create-vms-playbook.yml` (this writes the inventory to
`ansible/k3s/default/inventory` instead), then run
`ansible/k3s/default/k3s-playbook.yml` and
`ansible/rancher/default-ha/rancher-playbook.yml` (with `KUBECONFIG_FILE`
pointed at the k3s playbook's kubeconfig, since its default assumes RKE2)
the same way. `harvester-rancher-playbook.yml` itself only chains the RKE2 path.

## Upgrading Harvester

See [upgrade-harvester.yml](./upgrade-harvester.yml) and
[group_vars/all.yml.example](./group_vars/all.yml.example) for the required
variables (`harvester_host`, `harvester_user`, `harvester_password`,
`target_version`).

## Importing a Harvester cluster as downstream in Rancher

`import-downstream-playbook.yml` reuses the exact same Rancher-API import
logic already used by
[`ansible/rke2/airgap/playbooks/deploy/add-downstream-cluster.yml`](../rke2/airgap/playbooks/deploy/add-downstream-cluster.yml)
(Rancher login, the `tofu/rancher/import` module, registration token, manifest
apply, readiness checks) — unmodified. The only difference is how the target
cluster's kubeconfig is reached: the airgap playbook fetches it through a
bastion host, while this one uses the kubeconfig already written locally by
`ansible/rke2/default/rke2-playbook.yml`, since Harvester VMs are directly
reachable from the Ansible control host.

This creates **two clusters**: one running Rancher (cluster A, built with
`harvester-rancher-playbook.yml`) and a separate one to import as downstream
into it (cluster B). Importing a cluster into the Rancher instance running on
itself is unnecessary — Rancher already manages its own hosting cluster as the
built-in `local` cluster.

```bash
# 1. Stand up cluster A + Rancher (see previous section). Note the fqdn it
#    prints — that's the Rancher instance downstream clusters import into.
ansible-playbook ansible/harvester/harvester-rancher-playbook.yml

# 2. Point terraform.tfvars (or a separate tfvars file) at a *different* set
#    of nodes for cluster B, apply it, dump cluster_nodes_json to a different
#    path, then generate the inventory + install RKE2:
cd tofu/harvester/modules/vm
tofu apply -var-file=terraform-cluster-b.tfvars -auto-approve
mkdir -p /tmp/harvester-vms-b
tofu output -raw cluster_nodes_json > /tmp/harvester-vms-b/harvester-nodes.json
cd -
ansible-playbook ansible/harvester/create-vms-playbook.yml \
  -e "harvester_cluster_nodes_json_file=/tmp/harvester-vms-b/harvester-nodes.json"
ansible-playbook -i ansible/rke2/default/inventory/inventory.yml \
  ansible/rke2/default/rke2-playbook.yml

# 3. Import cluster B as downstream into cluster A's Rancher:
ansible-playbook ansible/harvester/import-downstream-playbook.yml \
  -e "rancher_hostname=<cluster A fqdn>"
```

Or run steps 2-3 in one go with the orchestrator (requires `rancher_hostname`
to already be set, since it targets a pre-existing Rancher instance):

```bash
ansible-playbook ansible/harvester/harvester-downstream-playbook.yml \
  -e "rancher_hostname=<cluster A fqdn>"
```

See `vars.yaml.example` for all the variables this step accepts
(`rancher_hostname`, `rancher_password`, `cluster_name`,
`harvester_kubeconfig_file`, ...).
