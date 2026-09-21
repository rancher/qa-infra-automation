output "fqdn" {
  value = aws_route53_record.aws_route53.fqdn
}

output "kube_api_host" {
  value       = local.node_ip[local.node_names[local.first_master_index].name]
  description = "Reachable IP of the cluster-init / master node (first etcd-having node, else first cp-having node). Public IP normally; private IP when airgap_setup/proxy_setup place nodes without one."
}

output "instance_public_ips" {
  description = "The public IP addresses assigned to the EC2 instances (empty list for airgap/proxy nodes)."
  value       = compact([for instance in aws_instance.node : instance.public_ip])
}

# Schema v2 (backwards compatible: v1 fields unchanged, new fields added).
# Consumers must not read secrets from here; only paths and addresses are exposed.
output "cluster_nodes_json" {
  description = "Complete node metadata for bridge script consumption (schema_version 2)."
  value = jsonencode({
    type = "cluster_nodes"
    metadata = {
      schema_version  = 2
      kube_api_host   = local.node_ip[local.node_names[local.first_master_index].name]
      fqdn            = aws_route53_record.aws_route53.fqdn
      ssh_user        = var.aws_ssh_user
      ssh_private_key = var.private_ssh_key
      airgap          = var.airgap_setup
      arch            = var.arch
      run_id          = var.run_id
      qa_infra_sha    = var.qa_infra_sha
    }
    nodes = [
      for node in local.node_names : {
        name        = node.name
        roles       = node.role
        public_ip   = aws_instance.node[node.name].public_ip
        private_ip  = aws_instance.node[node.name].private_ip
        instance_id = aws_instance.node[node.name].id
        az          = aws_instance.node[node.name].availability_zone
      }
    ]
    bastion = local.bastion_enabled ? {
      public_ip   = aws_instance.bastion[0].public_ip
      public_dns  = aws_instance.bastion[0].public_dns
      private_ip  = aws_instance.bastion[0].private_ip
      instance_id = aws_instance.bastion[0].id
    } : null
  })
}

output "bastion_public_ip" {
  description = "Public IP of the bastion, null when bastion.enabled is false."
  value       = local.bastion_enabled ? aws_instance.bastion[0].public_ip : null
}

output "bastion_public_dns" {
  description = "Public DNS name of the bastion (resolves to its private IP inside the VPC); null when disabled. Airgap runs use it as the registry hostname."
  value       = local.bastion_enabled ? aws_instance.bastion[0].public_dns : null
}

output "bastion_private_ip" {
  description = "Private IP of the bastion, null when disabled."
  value       = local.bastion_enabled ? aws_instance.bastion[0].private_ip : null
}

output "ssh_security_group_id" {
  description = "ID of the dedicated SSH security group created when create_ssh_security_group=true; null otherwise."
  value       = var.create_ssh_security_group ? aws_security_group.ssh[0].id : null
}

output "vpc_id" {
  description = "The VPC ID in use (var.aws_vpc)."
  value       = local.vpc_id
}

output "subnet_id" {
  description = "The subnet ID in use (var.aws_subnet)."
  value       = local.subnet_id
}

output "security_group_ids" {
  description = "The security group IDs in use — either var.aws_security_group if supplied, or the ephemerally created security group."
  value       = local.security_group_ids
}
