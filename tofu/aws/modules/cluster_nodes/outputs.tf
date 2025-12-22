output "fqdn" {
  value = aws_route53_record.aws_route53.fqdn
}

output "kube_api_host" {
  value       = aws_instance.node[local.node_names[local.first_etcd_index].name].public_ip
  description = "The public IP address of the first etcd node, or 'No etcd node found'."
}

output "instance_public_ips" {
  description = "The public IP addresses assigned to the EC2 instances"
  value       = [for instance in aws_instance.node : instance.public_ip]
}