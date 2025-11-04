provider "rancher2" {
  api_url   = var.fqdn
  token_key = var.api_key
  insecure  = var.insecure
}

resource "rancher2_cluster" "imported-cluster" {
  name = var.cluster_name
  description = "Cluster imported using qa-infra Ansible playbook"
  imported_config {
    private_registry_url = var.registry_url
  }
}
