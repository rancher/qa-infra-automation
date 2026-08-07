terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 3.0"
    }
}
}

provider "aws" {
  region = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

locals {
  # Ports the network load balancers forward on to the rancher targets. The
  # NLBs themselves carry no security group, so the listener ports must be
  # opened directly on the instances for the forwarded traffic to land.
  ports = ["80", "443", "6443", "9345"]

  # When no pre-existing security group is supplied, provision one inside the
  # airgap VPC so the module is self-contained. Callers can still pass their
  # own group id(s) via var.aws_security_group to reuse an existing group.
  create_security_group = length(var.aws_security_group) == 0
  security_group_ids    = local.create_security_group ? [aws_security_group.airgap[0].id] : var.aws_security_group
}

# Security group shared by the bastion, registry (when provisioned) and all
# airgap cluster nodes. It lives in the airgap VPC and:
#   * allows SSH from the operator (configurable CIDR, default anywhere),
#   * allows full intra-group traffic so the bastion can reach the nodes and
#     the RKE2/Rancher cluster nodes can talk to each other (etcd, kube-api,
#     flannel VXLAN, etc.) without enumerating every cluster port,
#   * opens the NLB listener ports so load-balanced traffic reaches the nodes,
#   * permits all egress.
# Note: airgap isolation is still enforced at the subnet level -- the airgap
# subnet has no route to an internet gateway -- so the permissive egress here
# does not break airgap-ness for the nodes in that subnet.
resource "aws_security_group" "airgap" {
  count       = local.create_security_group ? 1 : 0
  name        = "${var.aws_hostname_prefix}-airgap"
  description = "Security group for the ${var.aws_hostname_prefix} airgap deployment (bastion, registry, cluster nodes)"
  vpc_id      = var.aws_vpc

  # Operator SSH access to the bastion (and any instance sharing this group).
  dynamic "ingress" {
    for_each = toset(var.allowed_ssh_cidr)
    content {
      description = "SSH from ${ingress.value}"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  # Full intra-group communication: bastion -> nodes and node <-> node.
  ingress {
    description = "All traffic between instances in this security group"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # NLB listener ports forwarded on to the rancher targets.
  dynamic "ingress" {
    for_each = toset(local.ports)
    content {
      description = "LB listener ${ingress.value} from load balancer clients"
      from_port   = tonumber(ingress.value)
      to_port     = tonumber(ingress.value)
      protocol    = "tcp"
      cidr_blocks = var.allowed_lb_cidr
    }
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.aws_hostname_prefix}-airgap"
  }
}

# Bastion
module "bastion" {
  source = "./../ec2_instance"
  name = "${var.aws_hostname_prefix}-bastion"
  ami = var.aws_ami
  instance_type = var.instance_type
  subnet_id = var.aws_subnet_bastion
  ssh_key_name = var.ssh_key_name
  security_group_ids = local.security_group_ids
  volume_size = var.aws_volume_size
  user_id = var.user_id
  ssh_key = var.ssh_key
  associate_public_ip = true
}

# Registry instance
module "registry" {
  count = var.provision_registry ? 1 : 0
  source = "./../ec2_instance"
  name = "${var.aws_hostname_prefix}-registry"
  ami = var.aws_ami
  instance_type = var.instance_type
  subnet_id = var.aws_subnet_bastion
  ssh_key_name = var.ssh_key_name
  security_group_ids = local.security_group_ids
  volume_size = var.aws_volume_size
  user_id = var.user_id
  ssh_key = var.ssh_key
  associate_public_ip = true
}

# Load Balance
module "load_balancer" {
  count = can(var.node_groups["rancher"]) ? 1 : 0
  source = "./../load_balancer"
  name = var.aws_hostname_prefix
  internal = false
  subnet_id = var.aws_subnet_bastion
  vpc_id = var.aws_vpc
  ports = local.ports
}

# Internal Load Balance
module "internal_load_balancer" {
  count = can(var.node_groups["rancher"]) ? 1 : 0
  source = "./../load_balancer"
  name = "${var.aws_hostname_prefix}-internal"
  internal = true
  subnet_id = var.aws_subnet_airgap
  vpc_id = var.aws_vpc
  ports = local.ports
}

# Airgapped nodes
module "airgap_nodes" {
  source = "./../ec2_instance"
  for_each = toset(flatten([
    for group_name, count in var.node_groups : [
      for index in range(1, count + 1) : "${group_name}-${index}"
    ]
  ]))

  name = "${var.aws_hostname_prefix}-${each.value}"
  ami = var.aws_ami
  instance_type = var.instance_type
  subnet_id = var.aws_subnet_airgap
  ssh_key_name = var.ssh_key_name
  security_group_ids = local.security_group_ids
  volume_size = var.aws_volume_size
  user_id = var.user_id
  ssh_key = var.ssh_key
  associate_public_ip = false
}

locals {
  target_groups = toset(concat(module.load_balancer[0].target_groups, module.internal_load_balancer[0].target_groups))
  target_groups_map = {
    for tg in local.target_groups : tg.name => tg
  }
}

# Route53 record
module "route53" {
  count = can(var.node_groups["rancher"]) ? 1 : 0
  source = "./../route53"
  zone_name = var.aws_route53_zone
  record_name = var.aws_hostname_prefix
  dns_name = module.load_balancer[0].dns_name
}

# Internal Route53 record
module "internal_route53" {
  count = can(var.node_groups["rancher"]) ? 1 : 0
  source = "./../route53"
  zone_name = var.aws_route53_zone
  record_name = "${var.aws_hostname_prefix}-internal"
  dns_name = module.internal_load_balancer[0].dns_name
}

locals {
  rancher_node_target_group_product = flatten([
    for target_group in concat(module.load_balancer[0].target_groups, module.internal_load_balancer[0].target_groups) : [
      for id, instance in module.airgap_nodes : {
          arn = target_group.arn
          port = target_group.port
          node = instance.id
        } if startswith(id, "rancher-")
    ]
  ])
}

resource "aws_lb_target_group_attachment" "attachment-server" {
  # Using a "known after apply" value as a key can break tofu.
  for_each = zipmap(range(length(local.rancher_node_target_group_product)), local.rancher_node_target_group_product)
  target_group_arn = each.value.arn
  port = each.value.port
  target_id = each.value.node
  depends_on = [module.load_balancer, module.internal_load_balancer, module.airgap_nodes]
}
