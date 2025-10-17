output "cluster_id" {
    value = rancher2_cluster.custom-cluster.id
}

output "cluster_registration_token" {
    value = rancher2_cluster.custom-cluster.cluster_registration_token[0].token
}
