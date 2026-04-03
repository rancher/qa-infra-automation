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

output "cluster_nodes_json" {
  description = "Complete node metadata for bridge script consumption"
  value = jsonencode({
    type = "cluster_nodes"
    metadata = {
      kube_api_host      = aws_instance.node[local.node_names[local.first_etcd_index].name].public_ip
      fqdn               = aws_route53_record.aws_route53.fqdn
      ssh_user           = var.aws_ssh_user
    }
    nodes = [
      for node in local.node_names : {
        name       = node.name
        roles      = node.role
        public_ip  = aws_instance.node[node.name].public_ip
        private_ip = aws_instance.node[node.name].private_ip
      }
    ]
  })
}
