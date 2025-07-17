output "cluster_registration_token" {
  value = data.rancher2_cluster_v2.rancher2_cluster_v2.cluster_registration_token[0]["insecure_node_command"]
  sensitive = true
}