# Harvester

Ansible playbooks for operating Harvester itself and for deploying RKE2 +
Rancher onto nodes that already exist (for example VMs provisioned by hand
or via the Harvester UI/API). This directory does **not** provision
infrastructure — there is currently no `tofu/harvester` module and no
inventory-generation step here; bring your own inventory.

## Playbooks

| Playbook | Purpose |
|----------|---------|
| `upgrade-harvester.yml` | Upgrade a running Harvester cluster (via its API) and restart VMs afterward. |
| `harvester-rancher-playbook.yml` | Install RKE2 → deploy Rancher on an existing set of nodes, by chaining the unmodified `ansible/rke2/default` and `ansible/rancher/default-ha` playbooks. |

## Installing RKE2 and Rancher

`harvester-rancher-playbook.yml` is a two-line orchestrator:

```yaml
- import_playbook: ../rke2/default/rke2-playbook.yml
- import_playbook: ../rancher/default-ha/rancher-playbook.yml
```

It reuses those playbooks exactly as-is, the same way every other provider in
this repo does. It does not know anything about Harvester specifically — you
must already have nodes (e.g. Harvester VMs) reachable over SSH and a
matching Ansible inventory.

### Prerequisites

In addition to the [general ansible prereqs](../README.md):

* An Ansible inventory listing your target nodes/groups, as expected by
  `ansible/rke2/default/rke2-playbook.yml` (see that playbook and its
  [README](../rke2/default/README.md) for the required groups/host vars).
* `kube_api_host` and `fqdn` provided via `vars.yaml`, environment variables
  (`KUBE_API_HOST`, `FQDN`), or a terraform state file — see
  `ansible/rke2/default/rke2-playbook.yml` for the lookup order.
* `vars.yaml` files in each playbook's own directory (loaded relative to
  `playbook_dir`, so `ansible/harvester/vars.yaml` itself is **not** used by
  `harvester-rancher-playbook.yml` — see [vars.yaml.example](./vars.yaml.example)
  in this directory for details):
  * `ansible/rke2/default/vars.yaml` (RKE2 install settings — copy from
    `vars.yaml.example` in that directory)
  * `ansible/rancher/default-ha/vars.yaml` (Rancher chart/version settings —
    see that directory's [QUICKSTART.md](../rancher/default-ha/QUICKSTART.md)
    for a template)

### Running the pipeline

```bash
cp ansible/rke2/default/vars.yaml.example ansible/rke2/default/vars.yaml
# edit ansible/rancher/default-ha/vars.yaml per its QUICKSTART.md
# edit both vars.yaml files as needed

ansible-playbook -i <your-inventory> ansible/harvester/harvester-rancher-playbook.yml
```

Or run the two stages individually:

```bash
ansible-playbook -i <your-inventory> ansible/rke2/default/rke2-playbook.yml
ansible-playbook -i <your-inventory> ansible/rancher/default-ha/rancher-playbook.yml
```

## Upgrading Harvester

See [upgrade-harvester.yml](./upgrade-harvester.yml) and
[group_vars/all.yml.example](./group_vars/all.yml.example) for the required
variables (`harvester_host`, `harvester_user`, `harvester_password`,
`target_version`). This playbook only talks to the Harvester API on
`localhost` — no inventory of cluster nodes is needed.
