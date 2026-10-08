locals {
  master_instance = aws_instance.node[local.master_node_name]
  kube_api_host = (
    local.publish_ipv6_record ? try(local.master_instance.ipv6_addresses[0], "") :
    var.enable_public_ip ? coalesce(local.master_instance.public_ip, local.master_instance.private_ip) :
    local.master_instance.private_ip
  )
}

output "fqdn" {
  value = aws_route53_record.aws_route53.fqdn
}

output "kube_api_host" {
  value       = local.kube_api_host
  description = "The API host address (IPv4 or IPv6) of the cluster-init node."
}

output "instance_public_ips" {
  description = "The public IP addresses assigned to the EC2 instances"
  value       = [for instance in aws_instance.node : instance.public_ip]
}

output "instance_ipv6_addresses" {
  description = "The public IPv6 addresses assigned to the EC2 instances"
  value       = var.enable_ipv6 ? [for instance in aws_instance.node : try(instance.ipv6_addresses[0], "")] : []
}

output "cluster_nodes_json" {
  description = "Complete node metadata for bridge script consumption"
  value = jsonencode({
    type = "cluster_nodes"
    metadata = {
      kube_api_host   = local.kube_api_host
      fqdn            = aws_route53_record.aws_route53.fqdn
      ssh_user        = var.aws_ssh_user
      ssh_private_key = var.private_ssh_key
      bastion_ip      = local.create_bastion ? aws_instance.bastion[0].public_ip : ""
      bastion_dns     = local.create_bastion ? aws_instance.bastion[0].public_dns : ""
    }
    nodes = [
      for node in local.node_names : {
        name       = node.name
        roles      = node.role
        public_ip  = aws_instance.node[node.name].public_ip
        private_ip = aws_instance.node[node.name].private_ip
        ipv6       = var.enable_ipv6 ? try(aws_instance.node[node.name].ipv6_addresses[0], "") : ""
      }
    ]
  })
}

output "bastion_ip" {
  description = "The public IP addresses assigned to the bastion host"
  value       = local.create_bastion ? aws_instance.bastion[0].public_ip : ""
}

output "bastion_dns" {
  value       = local.create_bastion ? aws_instance.bastion[0].public_dns : ""
  description = "The public DNS of the AWS node"
}

output "bastion_ipv6" {
  value       = local.create_bastion && var.enable_ipv6 ? try(aws_instance.bastion[0].ipv6_addresses[0], "") : ""
  description = "The public IPv6 address of the AWS node"
}

output "bastion_user" {
  value       = var.aws_ssh_user
  description = "The SSH user for the bastion host"
}
