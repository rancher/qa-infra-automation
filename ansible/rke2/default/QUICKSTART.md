# Quickstart

## Prerequisites

1. Infrastructure Deployed: You must have nodes to install rke2 on, either by running `tofu apply` successfully or bringing your own. [Example tofu module](../../../tofu/aws/modules/cluster_nodes/QUICKSTART.md).
2. Ansible Installed: Ensure you have `ansible` installed locally.

## Steps

### Step 1: Setup Ansible Inventory

Before running the playbook, verify that your inventory file is correctly populated with the relevant data. Do one of the two steps below:

- If you brought up infrastructure from Tofu, you can generate the file:
  1. From the root of the repo, tell the automation scripts the relative directory where your terraform.tfstate file lives. For example:

      ```sh
      export TERRAFORM_NODE_SOURCE="tofu/aws/modules/cluster_nodes"
      ```
  2. From the root of the repo, use `envsubst` to generate the Ansible inventory file. 

      ```sh
      envsubst < ansible/rke2/default/inventory-template.yml > ansible/rke2/default/terraform-inventory.yml
      ```

- If wanting to fill in manually, or bringing your own nodes, see below example for what the file should look like. Note that the amount of hosts you have will directly correspond with the nodes in the resulting cluster:

  ```yaml
  # ./terraform-inventory.yml
  nodes:
    hosts:
      master: # One host must be named "master" -- this is the node that rke2 will be installed on first and other nodes will join to
        ansible_host: "1.2.3.4"         # node public ip
        ansible_role: "etcd,cp,worker"  # node role(s). Must include etcd for the first node.
        ansible_user: "ec2-user"        # ssh user
      node2:                            # This can be named whatever you want.
        ansible_host: "5.6.7.8" # node public ip
        ansible_role: "worker" # node role(s). Can be any combination of 'etcd', 'cp', and 'worker'.
        ansible_user: "ec2-user" # ssh user
  ```

Once you have your file populated, verify it has the correct data. Ensure you see your nodes listed in the JSON output - the IPs, ssh users, and node roles.

```sh
# From the repository root
ansible-inventory -i ansible/rke2/default/terraform-inventory.yml --list
```

### Step 2: Define Ansible Variables

You must tell Ansible which version of RKE2 to install and configure other deployment specifics. Create a file named `vars.yaml` in the `ansible/rke2/default/` directory. Note that `fqdn` and `kube_api_host` are not required *if using infrastructure from Tofu*.

`vars.yaml` Template:

```yaml
# rke2 version
kubernetes_version: 'v1.34.2+rke2r1'

# where to store the kubeconfig file
kubeconfig_file: './kubeconfig.yaml'

# network configuration
cni: "calico"
fqdn: a.b.c.d.sslip.io # Your FQDN, or a wildcard DNS like sslip.io with your IP
kube_api_host: a.b.c.d # Your initial node IP
```

### Step 2b: Configure RKE2 Options (Optional)

The `vars.yaml` file supports additional RKE2 configuration via `server_flags` and `worker_flags`:

```yaml
# Server configuration (control-plane nodes)
server_flags: |
  ingress-controller: traefik
  protect-kernel-defaults: true

# Worker configuration (agent nodes)
worker_flags: |
  protect-kernel-defaults: true
  node-label:
    - "workload=general"
```

**Common configurations:**

| Configuration | server_flags value |
|--------------|-------------------|
| Use Traefik (default) | `ingress-controller: traefik` |
| Use Nginx | `ingress-controller: ""` or omit |
| Disable ingress | `disable: rke2-ingress-nginx` |
| CIS hardening | `protect-kernel-defaults: true` |

See [RKE2 Server Config Reference](https://docs.rke2.io/reference/server_config) for all options.

### Step 3: Run the Playbook

Run the playbook targeting the inventory file located in the root directory.

```sh
# Syntax: ansible-playbook -i <inventory_path> <playbook_path>
ansible-playbook -i ansible/rke2/default/terraform-inventory.yml ansible/rke2/default/rke2-playbook.yml
```

### Step 4: Verify RKE2 Installation

Once the playbook completes successfully, verify the cluster status. You should be able to do this with kubectl locally, from the root of this repo.

```sh
kubectl --kubeconfig ansible/rke2/default/kubeconfig.yaml get nodes,pods -A -o wide
```
