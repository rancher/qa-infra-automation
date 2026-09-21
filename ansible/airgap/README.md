# ansible/airgap — K3s/RKE2 airgap install for the distros QA flow

Installs K3s or RKE2 **offline** on private `cluster_nodes` instances through a bastion,
using the official `install.sh` in offline mode. Driven by
[distros-test-framework](https://github.com/rancher/distros-test-framework) (`MODULE=airgap`,
`PROVISIONER_MODULE=qainfra`); usable by hand with `make cluster ENV=airgap AIRGAP_WORKFLOW=distros DISTRO=k3s`.

Not the Rancher HA airgap flow: that one lives in `ansible/<distro>/airgap` with `tofu/aws/modules/airgap`.

- Playbook: `airgap-playbook.yml` (validate → bastion prepare/artifacts/registry → master → servers → workers → cluster access).
- Roles: `airgap_bastion_prepare`, `airgap_artifacts`, `airgap_registry`, `airgap_image_publish`,
  `airgap_product_install`, `airgap_cluster_access` (under `ansible/roles/`).
- Contract (inventory groups, extra-vars, `airgap-facts.json`) and a hand-run example:
  [docs/guides/airgap-cluster-nodes.md](../../docs/guides/airgap-cluster-nodes.md).
- Tests: `python -m pytest tests/test_airgap_playbook_contract.py` (static contract + syntax-check of every product × method).

Secrets: `registry_username` / `registry_password` are read from `--extra-vars @file` (0600) and
every task that touches them or the kubeconfig content runs with `no_log`. Never pass them on the
command line.
