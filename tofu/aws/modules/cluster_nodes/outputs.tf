output "fqdn" {
  value = aws_route53_record.aws_route53.fqdn
}

output "kube_api_host" {
  value       = aws_instance.node[local.node_names[local.first_master_index].name].public_ip
  description = "Public IP of the cluster-init / master node: first etcd-having node if any, otherwise first cp-having node (cp-only + external datastore topology)."
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
      kube_api_host   = aws_instance.node[local.node_names[local.first_master_index].name].public_ip
      fqdn            = aws_route53_record.aws_route53.fqdn
      ssh_user        = var.aws_ssh_user
      ssh_private_key = var.private_ssh_key
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

output "ssh_security_group_id" {
  description = "ID of the dedicated SSH security group created when create_ssh_security_group=true; null otherwise."
  value       = var.create_ssh_security_group ? aws_security_group.ssh[0].id : null
}

output "vpc_id" {
  description = "The VPC ID in use (var.aws_vpc)."
  value       = local.vpc_id
  sensitive   = true
}

output "subnet_id" {
  description = "The subnet ID in use (var.aws_subnet)."
  value       = local.subnet_id
  sensitive   = true
}

output "security_group_ids" {
  description = "The security group IDs in use — either var.aws_security_group if supplied, or the ephemerally created security group."
  value       = local.security_group_ids
  sensitive   = true
}
