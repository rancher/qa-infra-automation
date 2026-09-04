output "ingress_rule_ids" {
  description = "IDs of the created ingress security group rules, keyed by CIDR"
  value       = { for k, v in aws_security_group_rule.ingress : k => v.id }
}

output "egress_rule_ids" {
  description = "IDs of the created egress security group rules, keyed by CIDR"
  value       = { for k, v in aws_security_group_rule.egress : k => v.id }
}
