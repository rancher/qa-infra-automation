# rke2_windows_agent

Installs RKE2 on a Windows Server host and joins it to an existing RKE2 cluster as an agent.

## Description

This role is the Windows counterpart to the `rke2_config` + `rke2_install` + `rke2_cluster`
chain used for Linux nodes. Windows has no server role in RKE2, so config generation,
installation, service registration and startup are collapsed into a single role.

What it does:

1. Ensures the Windows Server **Containers** feature is installed, rebooting if required.
2. Creates `C:\etc\rancher\rke2`, the binary directory, and the agent images directory.
3. Adds the RKE2 binary directories to the machine `PATH`.
4. Writes `C:\etc\rancher\rke2\config.yaml` with the server URL, token and node labels.
5. Downloads and runs `install.ps1` (skipped when the requested version is already installed).
6. Registers the `rke2` Windows service with `rke2.exe agent service --add` and starts it.
7. Waits for the host to be reachable again — starting the agent attaches an HNS
   external network to the physical NIC, which drops the SSH session — then waits for
   the kubelet kubeconfig to appear.

## Requirements

- Windows Server 2019 or 2022 LTSC. These are the versions RKE2 validates against.
- `ansible.windows` collection (`ansible-galaxy collection install -r requirements.yml`).
- OpenSSH Server on the host with PowerShell as the default shell. The AWS
  `cluster_nodes` module's `user_data` sets this up; for bring-your-own hosts see
  [the Windows agent guide](../../../docs/guides/rke2-windows-agent-aws.md).
- An existing RKE2 cluster whose CNI is **Calico** or **Flannel**.

> RKE2's default CNI, **Canal, does not support Windows**. Neither does dual-stack or
> Calico in BGP mode. A Windows agent joined to a Canal cluster registers and then stays
> `NotReady` forever, so this role asserts the CNI up front rather than letting the run
> fail 20 minutes later in `rke2_health_check`.

## Role Variables

Variables defined in `defaults/main.yml`:

| Variable | Default | Description |
|----------|---------|-------------|
| `rke2_windows_version` | `""` (channel latest) | RKE2 version to install, e.g. `v1.31.5+rke2r1`. A 40-hex-char commit hash is also accepted and installs that unreleased CI build via `install.ps1 -Commit`; such a build has no release checksum and is only reinstalled if the binary is altogether missing (no version-string match), so switching commits on a node that already has *some* rke2.exe requires removing it first |
| `rke2_windows_channel` | `stable` | Release channel; only used when the version is empty |
| `rke2_windows_install_script_url` | `.../rke2/master/install.ps1` | Floating install script URL |
| `rke2_windows_install_script_versioned_url` | `.../rke2/{{ version }}/install.ps1` | Version-pinned install script URL |
| `rke2_windows_config_dir` | `C:\etc\rancher\rke2` | Config directory |
| `rke2_windows_tar_prefix` | `C:/usr/local` | `install.ps1 -TarPrefix`; where the release tarball is unpacked |
| `rke2_windows_bin_dir` | `C:\usr\local\bin` | Directory holding `rke2.exe` |
| `rke2_windows_data_dir` | `C:\var\lib\rancher\rke2` | RKE2 data directory |
| `rke2_windows_temp_dir` | `C:\Windows\Temp` | Scratch directory for the downloaded `install.ps1` |
| `rke2_windows_service_name` | `rke2` | Name of the registered Windows service |
| `rke2_windows_node_labels` | `[]` | Extra `key=value` node labels; `role-worker=true` is always applied |
| `rke2_windows_node_ip` | `""` | Address the node advertises; empty means autodetect |
| `rke2_windows_vxlan_adapter` | `""` | Interface for the VXLAN VTEP, exported as `VXLAN_ADAPTER`. Required on multi-NIC or teamed hosts |
| `rke2_windows_additional_config` | `{}` | Extra keys merged into `config.yaml` |
| `rke2_windows_wait_timeout` | `900` | Seconds to wait for reboot and for the agent to come up |

Required from the inventory or playbook (not defaulted here):

| Variable | Source | Description |
|----------|--------|-------------|
| `kube_api_host` | inventory `all.vars` | Address of the cluster's first server node |
| `rke2_token` | `rke2_cluster` / token-slurp play | Cluster join token |
| `cni` | `vars.yaml` | Must be `calico` or `flannel` |
| `node_os` | inventory host var | Asserted to be `windows` |

## Dependencies

None declared. Requires a running RKE2 server, i.e. run after `rke2_cluster` has brought
up the control plane, and before `rke2_health_check` — that role fails the run unless
every node in the inventory is `Ready`.

## Example Playbook

```yaml
---
- name: Read the cluster join token
  hosts: master
  become: true
  tasks:
    - name: Slurp node token
      ansible.builtin.slurp:
        src: /var/lib/rancher/rke2/server/node-token
      register: rke2_node_token

    - name: Set the cluster token fact
      ansible.builtin.set_fact:
        rke2_cluster_token: "{{ rke2_node_token.content | b64decode | trim }}"

- name: Join Windows agents
  hosts: windows_workers
  gather_facts: true
  roles:
    - role: rke2_windows_agent
      vars:
        rke2_windows_version: "{{ kubernetes_version }}"
        rke2_windows_channel: "{{ channel | default('stable') }}"
        rke2_token: "{{ hostvars[groups['master'][0]]['rke2_cluster_token'] }}"
```

This is exactly what `ansible/rke2/shared/playbooks/setup/setup-windows-agent-nodes.yml`
does; the same two plays are also embedded in `ansible/rke2/default/rke2-playbook.yml`,
so `make cluster` builds a mixed Linux+Windows cluster in one pass.

## Verification

From a control-plane node:

```bash
kubectl get nodes -o wide            # the Windows node should be Ready
kubectl get node <win-node> -o jsonpath='{.metadata.labels.kubernetes\.io/os}'   # windows
```

On the Windows node itself:

```powershell
Get-Service rke2
Get-HnsNetwork | Select-Object Name, Type, ManagementIP   # ManagementIP must equal the node IP
Get-ChildItem c:\var\lib\rancher\rke2\agent\etc\cni\net.d # the CNI conf must exist
Get-Content c:\var\lib\rancher\rke2\agent\logs\kubelet.log -Tail 50
```

## Notes

- Ansible reaches these hosts over **SSH with PowerShell as the remote shell**, not WinRM.
  `scripts/generate_inventory.py` emits `ansible_shell_type: powershell`,
  `ansible_become: false` and `ansible_pipelining: false` for every `os: windows` node —
  pipelining is POSIX-only and breaks the `win_*` modules.
- Windows nodes live in the `windows_workers` inventory group, never in `workers`. The
  Linux plays exclude them with `hosts: all:!windows_workers`; they are all `become: true`
  and use systemd and dnf/zypper, none of which exist here.
- **The restart handler is a no-op on a first install.** `config.yaml` is written before
  the service exists, so the service this role registers and starts already has it —
  restarting it would only risk the disconnect below for nothing. The handler is guarded
  on `rke2_windows_agent_was_running`, sampled before any change is made, so it fires only
  when an already-running agent is reconfigured.
- Restarting rke2 tears down and re-creates the HNS external network bound to the host's
  physical NIC, so the SSH session usually dies mid-call. `win_service` has no timeout of
  its own and would block on the half-open socket, which is why the handler fires the
  restart with `async`/`poll: 0`, reconnects with `wait_for_connection`, and only then
  confirms the service is running. The `-o ServerAliveInterval` / `ServerAliveCountMax`
  options in `ansible.cfg` bound any remaining silent drop to roughly two minutes.
