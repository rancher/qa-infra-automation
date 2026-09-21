# Airgap K3s/RKE2 clusters with `cluster_nodes` (distros flow)

This is the airgap flow used by the distros QA nightlies through
[distros-test-framework](https://github.com/rancher/distros-test-framework). It is
different from `tofu/aws/modules/airgap` (Rancher HA airgap): here the **same
`cluster_nodes` module** provisions one bastion plus private nodes, and one Ansible
playbook installs K3s or RKE2 **offline with the official `install.sh`**.

## Topology

- Nodes: `airgap_setup = true` → no public IP. They sit in the caller-provided subnet
  (the shared QA subnet has no NAT, which is what makes them airgapped).
- Bastion: `bastion = { enabled = true }` → same subnet/SG/key pair, public IP. It is the
  only SSH entry point, downloads artifacts, and hosts the registry for the registry
  scenarios. Inside the VPC its EC2 public DNS name resolves to the private IP, so
  nodes reach the registry without leaving the VPC.
- Every run can be tagged with `run_id` (and `qa_infra_sha`) so cleanup can prove ownership.
- `airgap_setup = true` also checks, at plan time, that the subnet's effective route table (explicit association, else the VPC main table) has no IPv4 default route other than an internet gateway, and that the subnet does not auto-assign IPv6 (an IPv6 default route is egress as soon as nodes get an address; the QA subnets all route `::/0` to an IGW). The nodes are also probed for global IPv6 addresses at install time.

```hcl
module "cluster_nodes" {
  source       = "github.com/rancher/qa-infra-automation//tofu/aws/modules/cluster_nodes?ref=<sha>"
  # ...usual inputs...
  airgap_setup = true
  bastion      = { enabled = true, instance_type = "t3a.medium" }
  run_id       = "k3s-tarball-qainfra-42-a1b2c3"
  qa_infra_sha = "<sha>"
  arch         = "amd64"
}
```

`cluster_nodes_json` (schema 2) then carries `metadata.airgap`, `nodes[].private_ip`,
`nodes[].instance_id` and a `bastion` object (`public_ip`, `public_dns`, `private_ip`).
`kube_api_host` and the single-cp Route53 record use the master **private** IP.
Existing consumers see no change unless they set the new inputs.

## Playbook

`ansible/airgap/airgap-playbook.yml`, plays in order:

1. `localhost` — validate the scenario (product, version, method, arch, one bastion, one master, no CIS/protect-kernel flags).
2. `bastion` — `airgap_bastion_prepare` (kubectl of the cluster version for the bastion arch, podman), `airgap_artifacts` (download + sha256 verify; `install.sh` fetched at the commit the release tag resolves to, recorded in `manifest.json`), and for registry scenarios `airgap_registry` (TLS `registry` on podman, images pinned by digest, htpasswd in `private_registry`) + `airgap_image_publish` (podman pull/tag/push, catalog verified).
3. `master` → 4. `servers` (serial) → 5. `workers` — `airgap_product_install`: artifacts copied bastion→node by `scp` with an ephemeral ed25519 key minted on the bastion (authorized on the nodes for the run, revoked and deleted by the last two plays), `config.yaml` rendered, `registries.yaml` (private) or OS trust store (system_default), image tarballs into `agent/images` (tarball), then the **official installer** with `INSTALL_K3S_SKIP_DOWNLOAD=true` / `INSTALL_RKE2_ARTIFACT_PATH`.
6. `bastion` — `airgap_cluster_access`: kubeconfig at `/tmp/<product>_kubeconf.yaml` on the bastion (0600, SSH user; server rewritten to the master private IP), all nodes Ready, `airgap-facts.json` written on the controller.

### Inventory contract

```yaml
all:
  vars:
    ansible_user: ubuntu
    ssh_private_key_file: /path/key.pem   # controller path, used only by the ProxyCommand; never copied to the bastion
    ssh_key_name: jenkins-key             # informational (DTF passes it); the bastion uses an ephemeral key for scp
    bastion_host: <public ip>
    bastion_public_dns: <ec2 public dns>  # registry hostname / cert SAN
    bastion_private_ip: <private ip>
  hosts:
    bastion-0: { ansible_host: <public ip> }
    master:    { ansible_host: <private ip>, ansible_ssh_common_args: "... -o ProxyCommand='ssh -i key -W %h:%p ubuntu@<bastion>'" }
    worker-0:  { ansible_host: <private ip>, ansible_ssh_common_args: "..." }
  children:
    bastion: { hosts: { bastion-0: {} } }
    master:  { hosts: { master: {} } }
    servers: { hosts: {} }
    workers: { hosts: { worker-0: {} } }
```

No play overrides `ansible_ssh_common_args`; the ProxyCommand from the inventory is what
reaches the private nodes.

Always follow a run with `ansible-playbook -i inventory.yml airgap-cleanup-keys.yml` (the DTF
provisioner does so automatically, even when the install failed): it revokes the ephemeral scp
key on every host, including hosts the main playbook dropped after a failure.

### Extra-vars contract

| Variable | Values |
|---|---|
| `product` | `k3s` \| `rke2` |
| `kubernetes_version` | release version (`v1.36.0+k3s1`, `v1.36.0+rke2r1`); commits are not supported offline |
| `arch` | `amd64` \| `arm64` (node arch; the bastion downloads for its own arch separately) |
| `airgap_method` | `tarball` \| `private_registry` \| `system_default_registry` |
| `tarball_type` | `tar.zst` (default) \| `tar.gz` |
| `image_registry_url` | optional Prime base (`https://prime.ribs.rancher.io`); artifacts come from `<base>/<product>/<version>` for **both** products, never with a community fallback |
| `cni` | RKE2 only, e.g. `multus,canal` (drives image lists/tarballs AND `config.yaml`); when empty the `cni:` line of `server_flags` is used; if both are set they must match |
| `server_flags` / `worker_flags` | YAML scalars appended to `config.yaml` |
| `kubeconfig_file` | controller path for a protected (0600) copy of the kubeconfig |
| `airgap_facts_file` | controller path for `airgap-facts.json` |
| `registry_username` / `registry_password` | `private_registry` only; pass with `--extra-vars @secrets.json` (0600), never on the command line |

Artifacts are cached on the bastion under
`/opt/dtf-airgap/artifacts/<product>-<version>-<arch>-<community|prime>-<tar.zst|tar.gz|lists>-<cni key>/`
with a `manifest.json`; changing the CNI, format or origin selects another directory.

### `airgap-facts.json`

Written by the last play (paths and hostnames only, never credentials):
`schema_version`, `airgap_method`, `registry_mode`, `registry_host`, `registry_port`,
`registry_ca_path_bastion`, `registry_ca_path_nodes`, `artifacts_dir`, `artifact_origin`,
`release_url`, `bastion_kubeconfig_path`, `kubectl_path`, `bastion_host`, `bastion_public_dns`, `node_count`.

## Running by hand

```bash
# either: make infra-up ENV=airgap AIRGAP_WORKFLOW=distros DISTRO=k3s   (terraform.tfvars in the module dir)
# or:
tofu -chdir=<root using cluster_nodes> apply -var airgap_setup=true -var 'bastion={enabled=true}' ...
# write the inventory above from `tofu output -raw cluster_nodes_json` (infra-up does not
# generate it for this flow), then `make cluster ENV=airgap AIRGAP_WORKFLOW=distros DISTRO=k3s` or:
cd ansible/airgap
ansible-playbook -i inventory.yml airgap-playbook.yml \
  -e product=rke2 -e kubernetes_version=v1.36.0+rke2r1 -e arch=amd64 \
  -e airgap_method=tarball -e tarball_type=tar.zst -e cni=multus,canal \
  -e kubeconfig_file=$PWD/kubeconfig.yaml -e airgap_facts_file=$PWD/airgap-facts.json \
  -e ssh_private_key_file=~/.ssh/key.pem -e ssh_key_name=key
```

## Tests

- `tofu/aws/modules/cluster_nodes/tests/airgap_bastion.tftest.hcl` (mocked providers): `cd tofu/aws/modules/cluster_nodes && tofu init -backend=false && tofu test`
- `tests/test_cluster_nodes_airgap_contract.py`, `tests/test_airgap_playbook_contract.py`: `python -m pytest tests`

## Not covered yet

Windows agents, `profile: cis` / `protect-kernel-defaults` in airgap, RPM installs,
SELinux-enforcing nodes (`INSTALL_K3S_SKIP_DOWNLOAD` skips the k3s-selinux RPM and the
installer aborts on the chcon check; the policy package would have to be staged offline).
