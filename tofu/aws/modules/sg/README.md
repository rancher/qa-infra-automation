# sg

Grants a caller-supplied CIDR (typically a CI runner's detected public IP)
temporary all-protocol/all-port ingress and egress access on an existing
security group.

## Purpose

Replaces ad-hoc `aws ec2 authorize/revoke security-group-ingress/egress` CLI
calls in pipelines. Applying this module adds the rules; destroying it (or
removing the CIDR from `allowed_cidrs`) revokes them - so cleanup is handled
by the normal Tofu destroy lifecycle instead of a manual `post` step.

The target security group is resolved by **name** (not ID), so callers don't
need to know/pass around SG IDs - just the human-readable name used elsewhere
in the stack (e.g. `node_config.aws_security_group`).

## Prerequisites

- The target security group must already exist (this module only reads it via
  `data.aws_security_group`, it never creates or deletes the group itself).
- AWS credentials with `ec2:DescribeSecurityGroups`,
  `ec2:AuthorizeSecurityGroupIngress/Egress`, and
  `ec2:RevokeSecurityGroupIngress/Egress` permissions.

## Workflow

1. `tofu init`
2. `tofu apply -var-file=terraform.tfvars` - authorizes `allowed_cidrs` for
   all protocols/ports (ingress + egress) on the resolved security group.
3. `tofu destroy -var-file=terraform.tfvars` - revokes the rules added above.

Because state isn't guaranteed to persist across CI runs, re-applying after a
prior run failed to clean up can hit `InvalidPermission.Duplicate` if the rule
is still present on AWS but missing from state. Revoke the stale rule (e.g.
via `aws ec2 revoke-security-group-ingress/egress`) before re-applying in that
case, or reconcile via `tofu import`.

## Example

```hcl
module "runner_sg_access" {
  source = "./tofu/aws/modules/sg"

  security_group_name = "tf-pitdaily-sg"
  vpc_id               = "vpc-0123456789abcdef0"
  allowed_cidrs        = ["203.0.113.10"]
  description          = "jenkins-runner"
}
```

## Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `security_group_name` | Name of the existing security group to authorize/revoke rules on. | `string` | n/a |
| `vpc_id` | VPC ID to scope the `security_group_name` lookup to. | `string` | `null` |
| `allowed_cidrs` | Bare IPv4 addresses (no `/32` suffix) to grant temporary all-port ingress/egress access. | `list(string)` | `[]` |
| `description` | Description applied to the created security group rules. | `string` | `null` |

## Outputs

| Name | Description |
|------|-------------|
| `security_group_id` | Resolved ID of the security group looked up by `security_group_name`. |
| `ingress_rule_ids` | IDs of the created ingress rules, keyed by CIDR. |
| `egress_rule_ids` | IDs of the created egress rules, keyed by CIDR. |
