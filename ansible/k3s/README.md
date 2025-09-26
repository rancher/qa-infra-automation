# K3s HA Cluster Automation Playbook

This playbook automates the deployment of a highly available [K3s](https://k3s.io/) Kubernetes cluster using Ansible.  
It supports multi-node control plane (HA), worker nodes, and outputs a ready-to-use kubeconfig for remote access.

---

## Features

- **Serial master bootstrap:** Ensures the master node is installed and healthy before joining other nodes.
- **Parallel join:** Secondary control-plane and worker nodes join in parallel after master is ready.
- **Health checks:** Waits for API, kubeconfig, and readiness endpoints.
- **Automatic kubeconfig patch:** Rewrites kubeconfig to use the master’s external IP for remote access.
- **Idempotent:** Safe to re-run; only changes what’s needed.

---

## Prerequisites

- Python 3.8+ and [virtualenv](https://virtualenv.pypa.io/)
- Ansible 2.9+ installed in a virtual environment
- SSH access to all nodes (private key configured)
- Inventory file: `ansible/k3s/terraform-inventory.yml`
- Variables file: `vars.yml` in repo root
- Playbook: `ansible/k3s/k3s-playbook.yml`
- (Optional) Custom config: `ansible/k3s/ansible.cfg`
- Required roles/collections: `ansible/k3s/requirements.yml`

---

## Quickstart

### 1. Setup Python Virtual Environment

```sh
python3 -m venv .venv
source .venv/bin/activate
pip install --upgrade pip
pip install ansible
```

### 2. Install Ansible Collections/Roles

```sh
ansible-galaxy install -r ansible/k3s/requirements.yml
```

### 3. Run the Playbook

```sh
ANSIBLE_CONFIG=ansible/k3s/ansible.cfg \
ansible-playbook \
  -i ansible/k3s/terraform-inventory.yml \
  --private-key /root/.ssh/jenkins-elliptic-validation.pem \
  --extra-vars "@vars.yml" \
  ansible/k3s/k3s-playbook.yml
```

### 4. Output

- Kubeconfig will be saved as `ansible/k3s/k3s-kubeconfig.yaml` (with external master IP).

---

## Playbook Structure

| Play | Purpose                                      | Hosts         | Execution   |
|------|----------------------------------------------|---------------|-------------|
| 1    | Install and bootstrap master node            | master        | serial      |
| 2    | Join secondary control-plane nodes           | cp-*          | parallel    |
| 3    | Join worker nodes                            | worker-*      | parallel    |
| 4    | Patch and fetch kubeconfig for remote access | master        | run_once    |

---

## Dynamic Inventory Generation with Tofu

This project supports dynamic inventory generation using [Tofu](https://github.com/opentofu/opentofu) and the cluster nodes module.

1. **Provision Nodes with Tofu**

   Follow the instructions in the [Cluster Nodes README](https://github.com/rancher/qa-infra-automation/blob/main/tofu/aws/modules/cluster_nodes/README.md) to provision your infrastructure using `terraform.tfvars`.

2. **Set the Node Source Variable**

   Ensure the variable `TERRAFORM_NODE_SOURCE` points to your cluster nodes module path, for example:

   ```sh
   TERRAFORM_NODE_SOURCE="aws/modules/cluster_nodes"
   ```

   This variable tells Ansible where to find the Terraform state for inventory generation.

3. **Generate the Inventory**

   Use `envsubst` to create your dynamic inventory file:

   ```sh
   envsubst < inventory-template.yml > terraform-inventory.yml
   ```

   - The `inventory-template.yml` file should contain the key:
     ```yaml
     project_path: "$TERRAFORM_NODE_SOURCE"
     ```
     This lets Tofu know where to get inventory information.

4. **Check the Inventory**

   Verify your generated inventory with:

   ```sh
   ansible-inventory -i terraform-inventory.yml --graph --vars
   ```

5. **Continue with Playbook Execution**

   After generating the inventory, proceed to the [Quickstart](#quickstart) section above to run the playbook.

For more information on required variables, see the main [README](https://github.com/rancher/qa-infra-automation/blob/main/README.md).

---

## Troubleshooting

- For install errors, check the output and node logs:  
  `sudo journalctl -u k3s -n 50`
- Ensure all hosts are reachable via SSH and have Python 3 installed.
- Review `ansible/k3s/ansible.cfg` for custom settings.

---

## References

- [K3s Documentation](https://rancher.com/docs/k3s/latest/en/)
- [Ansible Documentation](https://docs.ansible.com/)
- [qa-infra-automation](https://github.com/rancher/qa-infra-automation)

---

## Example Manual Inventory

```ini
[master]
master ansible_host=<IP or fqdn>

[cp-*]
cp-0 ansible_host=<IP or fqdn>
cp-1 ansible_host=<IP or fqdn>

[worker-*]
worker-0 ansible_host=<IP or fqdn>
```

---

## Example vars.yml

```yaml
k3s_token: "your-cluster-token"
k3s_version: "v1.29.4+k3s1"
fqdn: "your-fqdn"
kube_api_host: "51.52.111.112"
cni: "flannel"
