# Grants a caller-supplied CIDR (typically a CI runner's detected public IP)
# temporary all-protocol/all-port ingress and egress access on an existing
# security group. Intended to replace ad-hoc `aws ec2 authorize/revoke
# security-group-ingress/egress` CLI calls in pipelines: applying this module
# adds the rules, destroying it (or removing the CIDR from the list) revokes
# them, so cleanup is handled by the normal Terraform destroy lifecycle
# instead of a manual `post` step.
resource "aws_security_group_rule" "ingress" {
  for_each = toset(var.allowed_cidrs)

  type              = "ingress"
  security_group_id = var.security_group_id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["${each.value}/32"]
  description       = coalesce(var.description, "temporary all-port ingress for ${each.value}")
}

resource "aws_security_group_rule" "egress" {
  for_each = toset(var.allowed_cidrs)

  type              = "egress"
  security_group_id = var.security_group_id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["${each.value}/32"]
  description       = coalesce(var.description, "temporary all-port egress for ${each.value}")
}
