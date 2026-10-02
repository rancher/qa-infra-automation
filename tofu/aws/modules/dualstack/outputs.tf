output "fqdn" {
  value = aws_route53_record.aws_route53.fqdn
}

output "kube_api_host" {
  value       = var.kube_api_host_ipv6 || !var.enable_public_ip ? aws_instance.node[local.node_names[local.first_etcd_index].name].ipv6_addresses[0] : aws_instance.node[local.node_names[local.first_etcd_index].name].public_ip
  description = "The API host IP address (IPv4 or IPv6) of the first etcd node."
}

output "instance_public_ips" {
  description = "The public IP addresses assigned to the EC2 instances"
  value       = [for instance in aws_instance.node : instance.public_ip]
}

output "instance_ipv6_addresses" {
  description = "The public IPv6 addresses assigned to the EC2 instances"
  value       = [for instance in aws_instance.node : instance.ipv6_addresses[0]]
}

output "cluster_nodes_json" {
  description = "Complete node metadata for bridge script consumption"
  value = jsonencode({
    type = "cluster_nodes"
    metadata = {
      kube_api_host   = var.kube_api_host_ipv6 || !var.enable_public_ip ? aws_instance.node[local.node_names[local.first_etcd_index].name].ipv6_addresses[0] : aws_instance.node[local.node_names[local.first_etcd_index].name].public_ip
      fqdn            = aws_route53_record.aws_route53.fqdn
      ssh_user        = var.aws_ssh_user
      ssh_private_key = var.private_ssh_key
      bastion_ip      = var.no_of_bastion_nodes != 0 ? aws_instance.bastion[0].public_ip : ""
      bastion_dns     = var.no_of_bastion_nodes != 0 ? aws_instance.bastion[0].public_dns : ""
    }
    nodes = [
      for node in local.node_names : {
        name       = node.name
        roles      = node.role
        public_ip  = aws_instance.node[node.name].public_ip
        private_ip = aws_instance.node[node.name].private_ip
        ipv6       = aws_instance.node[node.name].ipv6_addresses[0]
      }
    ]
  })
}

output "bastion_ip" {
  description = "The public IP addresses assigned to the bastion host"
  value = var.no_of_bastion_nodes != 0 ? aws_instance.bastion[0].public_ip : ""
}

output "bastion_dns" {
  value = var.no_of_bastion_nodes != 0 ? aws_instance.bastion[0].public_dns : ""
  description = "The public DNS of the AWS node"
}

output "bastion_ipv6" {
  value = var.no_of_bastion_nodes != 0 ? aws_instance.bastion[0].ipv6_addresses[0] : ""
  description = "The public IPv6 address of the AWS node"
}

output "bastion_user" {
  value = var.aws_ssh_user
  description = "The SSH user for the bastion host"
}
