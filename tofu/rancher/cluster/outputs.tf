output "name" {
  value = data.rancher2_cluster_v2.rancher2_cluster_v2.name
}

output "vpc_id" {
  description = "The VPC ID used for the AWS node pool — either node_config.aws_vpc if supplied, or the ephemerally created VPC. Null for non-aws cloud_provider."
  value       = var.cloud_provider == "aws" ? local.vpc_id : null
}

output "subnet_id" {
  description = "The subnet ID used for the AWS node pool — either node_config.aws_subnet if supplied, or the ephemerally created subnet. Null for non-aws cloud_provider."
  value       = var.cloud_provider == "aws" ? local.subnet_id : null
}

output "security_group_ids" {
  description = "The security group IDs used for the AWS node pool — either node_config.aws_security_group if supplied, or the ephemerally created security group. Null for non-aws cloud_provider."
  value       = var.cloud_provider == "aws" ? local.security_group_ids : null
}
