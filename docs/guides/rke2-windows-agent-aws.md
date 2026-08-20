# Add a Windows Agent to an RKE2 Cluster on AWS

> **Estimated time:** ~25 minutes
>
> **What you'll end up with:** A mixed RKE2 cluster — Linux control plane and workers plus one or more Windows Server agents — able to schedule both Linux and Windows pods over a shared Calico or Flannel overlay.

## Before you start

- Complete the [RKE2 on AWS guide](rke2-default-aws.md). Everything here builds on that setup.
- Install the Ansible collections, including `ansible.windows`:
  ```bash
  ansible-galaxy collection install -r requirements.yml
  ```

### What RKE2 supports on Windows

These are upstream constraints, not choices this repo made
([RKE2 requirements](https://docs.rke2.io/install/requirements)):

| | |
|---|---|
| **CNI** | **Calico or Flannel only.** RKE2's default, **Canal, does not support Windows** |
| **OS** | Windows Server 2019 or 2022 LTSC |
| **Role** | Agent only — there is no Windows server/control-plane role |
| **Not supported** | Dual-stack, Calico in BGP mode |
| **Extra ports** | UDP 4789 (VXLAN overlay), TCP 10250 (kubelet) |

The playbook fails immediately if `cni` is anything other than `calico` or `flannel` while
a Windows node is in the inventory, rather than letting the run die 20 minutes later on a
node that is registered but permanently `NotReady`.

## Step 1: Add a Windows node group

In `tofu/aws/modules/cluster_nodes/terraform.tfvars`, add the two Windows-specific
variables and a node group with `os = "windows"`:

```hcl
# Windows Server 2022 LTSC AMI for your region. Find one with:
#   aws ec2 describe-images --owners amazon --region us-east-2 \
#     --filters "Name=name,Values=Windows_Server-2022-English-Full-Base-*" \
#     --query 'reverse(sort_by(Images,&CreationDate))[:1].[ImageId,Name]' --output text
aws_ami_windows       = "ami-xxxxxxxxxxxxxxxxx"
instance_type_windows = "t3.xlarge"     # Windows + containerd needs the headroom

nodes = [
  { count = 1, role = ["etcd", "cp", "worker"] },
  { count = 1, role = ["worker"] },
  { count = 1, role = ["worker"], os = "windows" },
]
```

Windows groups must be `role = ["worker"]`, and at least one **linux** group must still
carry `cp`. Both are enforced at plan time.

Optional extras:

```hcl
aws_volume_size_windows = 80      # default 50; the AMI's own 30 GiB is too small
windows_enable_rdp      = true    # opens 3389 to ssh_allowed_cidrs for debugging
```

## Step 2: Provision

```bash
make infra-up
```

Alongside the instances this creates a `<prefix>-windows` security group allowing UDP 4789
and TCP 10250 from the VPC CIDR, attached to **both** the Linux and Windows nodes — VXLAN
is bidirectional, so opening it only on the Windows side is not enough.

The Windows `user_data` installs OpenSSH Server, sets PowerShell as the default shell,
installs your `public_ssh_key` into `C:\ProgramData\ssh\administrators_authorized_keys`,
and enables the Containers feature, which reboots the instance. **Expect the node to take
5–10 minutes to become reachable** — considerably longer than a Linux node.

Confirm the generated inventory placed the node correctly:

```bash
ansible-inventory -i ansible/rke2/default/inventory/inventory.yml --graph
```

```
@all:
  |--@master:
  |  |--master
  |--@workers:
  |  |--worker-0
  |--@windows_workers:
  |  |--windows-worker-0
```

The Windows host must be in `windows_workers` and **not** in `workers`. The Linux plays
run against `all:!windows_workers`; they are all `become: true` and use systemd and
dnf/zypper, none of which exist on Windows.

Then check connectivity:

```bash
ansible -i ansible/rke2/default/inventory/inventory.yml windows_workers -m ansible.windows.win_ping
ansible -i ansible/rke2/default/inventory/inventory.yml 'all:!windows_workers' -m ping
```

## Step 3: Set a Windows-capable CNI

In `ansible/rke2/default/vars.yaml`:

```yaml
kubernetes_version: 'v1.34.2+rke2r1'
cni: "calico"        # or "flannel" — NOT canal
kubeconfig_file: './kubeconfig.yaml'
```

No CNI tuning is needed for the default path: the bundled `rke2-calico` chart already
ships `bgp: Disabled`, `encapsulation: VXLAN` and `ipamConfig.strictAffinity: true`, which
is exactly what Windows requires. If you do need to override chart values (MTU, pod CIDR),
set `rke2_cni_values_content` and the `rke2_config` role writes a `HelmChartConfig` into
the server manifests directory before first start:

```yaml
rke2_cni_values_content: |
  installation:
    calicoNetwork:
      mtu: 1400
```

## Step 4: Deploy

For a brand-new cluster, the Windows plays are part of the main playbook:

```bash
make cluster
```

To add Windows agents to a cluster that is **already running**:

```bash
make windows-agents
```

Both paths read the join token from the master and run the `rke2_windows_agent` role,
which installs the Containers feature, writes `C:\etc\rancher\rke2\config.yaml`, runs
`install.ps1`, registers the `rke2` Windows service and starts it.

## Step 5: Verify

```bash
kubectl --kubeconfig ansible/rke2/default/kubeconfig.yaml get nodes -o wide
```

```
NAME               STATUS   ROLES                       VERSION            OS-IMAGE
master             Ready    control-plane,etcd,master   v1.34.2+rke2r1     SUSE Linux Enterprise Server 15 SP7
worker-0           Ready    <none>                      v1.34.2+rke2r1     SUSE Linux Enterprise Server 15 SP7
windows-worker-0   Ready    <none>                      v1.34.2+rke2r1     Windows Server 2022 Datacenter
```

Confirm the OS label and, on a Calico run, that the IP pool is in VXLAN mode:

```bash
kubectl get node windows-worker-0 -o jsonpath='{.metadata.labels.kubernetes\.io/os}'   # windows
kubectl get ippool default-ipv4-ippool -o jsonpath='{.spec.vxlanMode}'                 # Always
```

### Schedule a Windows pod

```bash
kubectl run winweb --image=mcr.microsoft.com/windows/servercore:ltsc2022 \
  --overrides='{"spec":{"nodeSelector":{"kubernetes.io/os":"windows"}}}' \
  --command -- powershell -Command "Start-Sleep -Seconds 3600"

kubectl get pod winweb -o wide
```

Pulling a Windows base image is slow — several minutes on first use. To prove cross-OS
overlay networking, curl the Windows pod's IP from a Linux pod.

## Troubleshooting

**Ansible can't reach the Windows node**

Give it 5–10 minutes: the `user_data` reboot happens after OpenSSH is configured. Then:

```bash
ssh -i ~/.ssh/id_ed25519 Administrator@<public-ip> 'hostname'
```

A password prompt means the authorized-keys file was not written. Retrieve the
Administrator password and check over RDP or EC2 Serial Console:

```bash
tofu -chdir=tofu/aws/modules/cluster_nodes output -json windows_administrator_passwords
```

(That output requires `private_ssh_key` to be set in your tfvars; it is deliberately kept
out of `cluster_nodes_json`, which gets written to a temp file and CI logs.)

**Node registers but stays `NotReady`**

Almost always the CNI. Verify `cni` is `calico` or `flannel`, then on the node:

```powershell
Get-Service rke2
Get-HnsNetwork | Select-Object Name, Type, ManagementIP   # ManagementIP must equal the node IP
Get-ChildItem c:\var\lib\rancher\rke2\agent\etc\cni\net.d # the CNI conf must exist
Get-Content c:\var\lib\rancher\rke2\agent\logs\kubelet.log -Tail 50
```

**Pods on Windows can't reach Linux pods**

UDP 4789 is blocked in one direction. Confirm the `<prefix>-windows` security group is
attached to the Linux nodes too, not just the Windows ones.

**Wrong network adapter picked for the overlay**

On a multi-NIC or teamed host, set the adapter explicitly:

```yaml
rke2_windows_vxlan_adapter: "Ethernet 2"
```

**`make bootstrap-python` or a Linux play touches the Windows node**

The host is in the wrong group. Regenerate the inventory and check `--graph` again;
`ansible/_inventory-schema.yaml` routes `os: windows` nodes to `windows_workers`.

For more, see [Troubleshooting](../reference/troubleshooting.md) and the
[rke2_windows_agent role README](../../ansible/roles/rke2_windows_agent/README.md).

## Next Steps

- [Deploy Rancher](rancher-ha.md) on top of the cluster
- [Inventory format reference](../reference/inventory-format.md) for the `os` and
  `ssh_user` node fields
- [Windows air-gap install](https://docs.rke2.io/install/windows_airgap) — not yet wired
  into this repo's airgap environment
