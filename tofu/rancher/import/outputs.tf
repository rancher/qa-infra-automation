output "cluster_id" {
    value = rancher2_cluster.imported-cluster.id
}

output "cluster_registration_token" {
    value = rancher2_cluster.imported-cluster.cluster_registration_token[0].token
}
