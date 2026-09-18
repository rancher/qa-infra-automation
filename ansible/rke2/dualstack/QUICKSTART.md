# Quickstart

> **📖 Looking for an end-to-end guide?** See [RKE2 on AWS](../../../docs/guides/rke2-default-aws.md) or [RKE2 on your own nodes](../../../docs/guides/rke2-default-byo.md) for step-by-step instructions that cover infrastructure through verification.

## Prerequisites

1. Infrastructure Deployed: You must have nodes to install rke2 on, either by running `tofu apply` successfully or bringing your own. [Example tofu module](../../../tofu/aws/modules/cluster_nodes/QUICKSTART.md).
2. Ansible Installed: Ensure you have `ansible` installed locally.

## Steps

### Step 1: Setup Ansible Inventory

Before running the playbook, verify that your inventory file is correctly populated with the relevant data. Do one of the two steps below:

- **If you brought up infrastructure from Tofu via `make infra-up ENV=dualstack`**, the inventory file is automatically generated at `ansible/rke2/default/inventory/inventory.yml` and includes global variables (`fqdn`, `kube_api_host`) and host groups (`master`, `servers`, `workers`).

- **If bringing your own nodes or filling in manually**, create an inventory file with this structure:

  ```yaml
  # inventory.yml
  all:
  vars:
    ansible_ssh_common_args: -o ProxyCommand='ssh -i {{ ansible_ssh_private_key_file
      }} -W %h:%p {{ bastion_user }}@{{ bastion_host }} -o StrictHostKeyChecking=no
      -o UserKnownHostsFile=/dev/null' -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
    ansible_user: <Ansible_Node_User>
    kube_api_host: 1.2.3.4
    fqdn: your-cluster-fqdn.example.com
    bastion_host: <Bastion_IP>
    bastion_user: <Bastion_User>
    bastion_dns: <Bastion_DNS>
    ansible_ssh_private_key_file: /Path/To/jenkins-distros-qa-rsa.pem
  hosts:
    master:
      ansible_host: 1.2.3.5
      ansible_host_ipv6: <IPV6_Address>
      node_roles:
      - etcd
      rke2_node_role: master
      ansible_ssh_private_key_file: /Path/To/jenkins-distros-qa-rsa.pem
    cp-0:
      ansible_host: 1.2.3.6
      ansible_host_ipv6: <IPV6_Address>
      node_roles:
      - cp
      rke2_node_role: server
      ansible_ssh_private_key_file: /Path/To/jenkins-distros-qa-rsa.pem
    worker-0:
      ansible_host: 1.2.3.7
      ansible_host_ipv6: <IPV6_Address>
      node_roles:
      - worker
      rke2_node_role: agent
      ansible_ssh_private_key_file: /Path/To/jenkins-distros-qa-rsa.pem
  children:
    bastion:
      hosts:
        bastion-node:
          ansible_host: '{{ bastion_host }}'
          ansible_user: '{{ bastion_user }}'
          ansible_ssh_common_args: -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null
    master:
      hosts:
        master:
          ansible_host: 1.2.3.5
          ansible_host_ipv6: <IPv6_Address>
      hosts:
        cp-0:
          ansible_host: 1.2.3.6
          ansible_host_ipv6: <IPv6_Address>
    workers:
      hosts:
        worker-0:
          ansible_host: 1.2.3.7
          ansible_host_ipv6: <IPv6_Address>

  ```

Once you have your inventory file, verify it has the correct data:

```sh
ansible-inventory -i ansible/rke2/dualstack/inventory/inventory.yml --list
```

### Step 2: Define Ansible Variables - Setup vars.yaml file:

You must tell Ansible which version of RKE2 to install and configure other deployment specifics. Create a file named `vars.yaml` in the `ansible/rke2/dualstack/` directory. Sample references can be found in the `ansible/rke2/dualstack/examples` directory.
- Copy examples/vars.ipv6.yaml to vars.yaml - for IPv6 ONLY scenario
- Copy examples/vars.dualstack.ipv6.yaml to vars.yaml - for Dualstack scenario but IPv6 first and IPv4 second setup.
- Copy examples/vars.dualstack.yaml to vars.yaml - for Dualstack scenario but IPv4 first and IPv6 second setup.

**Note:** If using Tofu-generated infrastructure, `fqdn` and `kube_api_host` are automatically included in the inventory file and do not need to be specified here.

`vars.yaml` Template:

```yaml
# rke2 version
kubernetes_version: 'v1.34.2+rke2r1'

# network configuration
cni: "calico"

# Only required if using manual inventory (not Tofu-generated):
# fqdn: a.b.c.d.sslip.io # Your FQDN, or a wildcard DNS like sslip.io with your IP
# kube_api_host: a.b.c.d # Your initial node IP
```

The kubeconfig is written to `ansible/rke2/dualstack/kubeconfig.yaml` on completion.

### Step 3: Run the Playbook

**Via Makefile (recommended)** — run from the repository root:

```sh
make cluster ENV=dualstack
```

**Manually** — run from the repository root:

```sh
ansible-playbook -i ansible/rke2/dualstack/inventory/inventory.yml ansible/rke2/dualstack/playbooks/rke2-playbook-dualstack.yml
```

**Use the following vars.yaml files for the corresponding playbooks:**
1. Dualstack IPv4 setup:
`examples/vars.dualstack.yaml` -> `ansible/rke2/dualstack/playbooks/rke2-playbook-dualstack.yml`
2. Dualstack IPv6 Setup:
`examples/vars.dualstack-ipv6.yaml` -> `ansible/rke2/dualstack/playbooks/rke2-playbook-dualstack.yml`
3. IPv6 ONLY Setup:
`examples/vars.ipv6.yaml` -> `ansible/rke2/dualstack/playbooks/rke2-playbook-ipv6.yml`

Note: The default in the Makefile uses `ansible/rke2/dualstack/playbooks/rke2-playbook-dualstack.yml`. If you need to change to ipv6, please update the Makefile manually, to be able to use `make cluster ENV=dualstack` command for IPv6 only setup. 


#### Optional: Run Specific Phases Using Tags

The role-based architecture supports selective execution using Ansible tags. See [README.md](./README.md) for the full list of available tags and examples.

### Step 4: Verify RKE2 Installation

Once the playbook completes successfully, verify the cluster status. You should be able to do this with kubectl locally, from the root of this repo.

```sh
kubectl --kubeconfig ansible/rke2/dualstack/kubeconfig.yaml get nodes,pods -A -o wide
```
You can also run `make status ENV=dualstack` to get the node, pods output for the rke2 cluster status. 

Note: For IPv6 only scenario, you will have to login to the bastion node to be able to run kubectl commands. The ~/.kube/config file is updated with the rke2 cluster kubeconfig file content on the bastion node for using kubectl commands. 

### Step 5: Destroy setup: 
```
make infra-down ENV=dualstack
```

### Summary: 
1. Setup vars.yaml file in ansible/rke2/dualstack folder. 
2. Setup terraform.tfvars in tofu/aws/modules/dualstack folder.
3. Make sure the correct playbook is being called per the required scenario in Makefile. 
4. Run to setup inventory and install rke2 cluster: 
```
make infra-up ENV=dualstack && make cluster ENV=dualstack && make infra-output ENV=dualstack
```
5. To destroy: 
```
make infra-down ENV=dualstack
```