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

output "windows_instance_public_ips" {
  description = "The public IP addresses assigned to the EC2 instances for windows"
  value       = [for instance in aws_instance.windows : instance.public_ip]
}

output "cluster_nodes_json" {
  description = "Complete node metadata for bridge script consumption"
  value = jsonencode({
    type = "cluster_nodes"
    metadata = {
      kube_api_host    = aws_instance.node[local.node_names[local.first_master_index].name].public_ip
      fqdn             = aws_route53_record.aws_route53.fqdn
      ssh_user         = var.aws_ssh_user
      ssh_private_key  = var.private_ssh_key
    }
    nodes = concat(
      # Linux nodes
      [
        for name, instance in aws_instance.node : {
          name       = name
          roles      = local.linux_instances_map[name].role # References your master/cp mappings
          public_ip  = instance.public_ip
          private_ip = instance.private_ip
          os         = "linux"
        }
      ],
      # Windows nodes
      [
        for name, instance in aws_instance.windows : {
          name       = name
          roles      = ["worker"]
          public_ip  = instance.public_ip
          private_ip = instance.private_ip
          os         = "windows"
        }
      ]
    )
  })
}

output "ssh_security_group_id" {
  description = "ID of the dedicated SSH security group created when create_ssh_security_group=true; null otherwise."
  value       = var.create_ssh_security_group ? aws_security_group.ssh[0].id : null
}
