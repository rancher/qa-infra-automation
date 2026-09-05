# Grants a caller-supplied CIDR (typically a CI runner's detected public IP)
# temporary all-protocol/all-port ingress and egress access on an existing
# security group. Intended to replace ad-hoc `aws ec2 authorize/revoke
# security-group-ingress/egress` CLI calls in pipelines: applying this module
# adds the rules, destroying it (or removing the CIDR from the list) revokes
# them, so cleanup is handled by the normal Terraform destroy lifecycle
# instead of a manual `post` step.
#
# The target security group is resolved by name (not ID) so callers don't
# need to know/pass around SG IDs - just the human-readable name used
# elsewhere in the stack (e.g. node_config.aws_security_group).
data "aws_security_group" "this" {
  name   = var.security_group_name
  vpc_id = var.vpc_id
}

resource "aws_security_group_rule" "ingress" {
  for_each = toset(var.allowed_cidrs)

  type              = "ingress"
  security_group_id = data.aws_security_group.this.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["${each.value}/32"]
  description       = coalesce(var.description, "temporary all-port ingress for ${each.value}")
}

resource "aws_security_group_rule" "egress" {
  for_each = toset(var.allowed_cidrs)

  type              = "egress"
  security_group_id = data.aws_security_group.this.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["${each.value}/32"]
  description       = coalesce(var.description, "temporary all-port egress for ${each.value}")
}
