output "security_group_id" {
  description = "Resolved ID of the security group looked up by security_group_name"
  value       = data.aws_security_group.this.id
}

output "ingress_rule_ids" {
  description = "IDs of the created ingress security group rules, keyed by CIDR"
  value       = { for k, v in aws_security_group_rule.ingress : k => v.id }
}

output "egress_rule_ids" {
  description = "IDs of the created egress security group rules, keyed by CIDR"
  value       = { for k, v in aws_security_group_rule.egress : k => v.id }
}
