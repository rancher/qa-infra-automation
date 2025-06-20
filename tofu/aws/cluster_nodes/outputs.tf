output "fqdn" {
  value = aws_route53_record.aws_route53.fqdn
}

output "kube_api_host" {
  value       = aws_instance.node[local.node_names[local.first_etcd_index].name].public_ip
  description = "The public IP address of the first etcd node, or 'No etcd node found'."
}