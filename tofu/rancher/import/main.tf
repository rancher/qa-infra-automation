provider "rancher2" {
  api_url   = var.fqdn
  token_key = var.api_key
  insecure  = var.insecure
}

resource "rancher2_cluster" "custom-cluster" {
  name = var.cluster_name
  description = "Cluster imported using qa-infra Ansible playbook"
}

# resource "rancher2_cluster_v2" "custom-cluster" {
#   name = var.cluster_name
    # description = "Cluster imported using qa-infra Ansible playbook"
#   kubernetes_version = "rke2-/k3s-version"
# }
