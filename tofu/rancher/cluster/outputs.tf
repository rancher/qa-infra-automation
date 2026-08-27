output "name" {
  value = data.rancher2_cluster_v2.rancher2_cluster_v2.name
}

output "vpc_id" {
  description = "The VPC ID used for the AWS node pool (node_config.aws_vpc). Null for non-aws cloud_provider."
  value       = var.cloud_provider == "aws" ? local.vpc_id : null
  sensitive   = true
}

output "subnet_id" {
  description = "The subnet ID used for the AWS node pool (node_config.aws_subnet). Null for non-aws cloud_provider."
  value       = var.cloud_provider == "aws" ? local.subnet_id : null
  sensitive   = true
}

output "security_group_names" {
  description = "The security group names used for the AWS node pool — either node_config.aws_security_group if supplied, or the ephemerally created security group's name. Null for non-aws cloud_provider."
  value       = var.cloud_provider == "aws" ? local.security_group_names : null
  sensitive   = true
}
