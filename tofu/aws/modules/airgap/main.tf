terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 3.0"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

# Bastion
module "bastion" {
  source = "./../ec2_instance"
  name = "${var.aws_hostname_prefix}-bastion"
  ami = var.aws_ami
  instance_type = var.instance_type
  subnet_id = var.aws_subnet
  ssh_key_name = var.ssh_key_name
  security_group_ids = var.aws_security_group
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
  subnet_id = var.aws_subnet
  ssh_key_name = var.ssh_key_name
  security_group_ids = var.aws_security_group
  volume_size = var.aws_volume_size
  user_id = var.user_id
  ssh_key = var.ssh_key
  associate_public_ip = true
}

locals {
  ports = ["80", "443", "6443", "9345"]

  rancher_node_target_group_product = flatten([
    for target_group in local.target_groups_map : [
      for node in [for key, instance in module.airgap_nodes : instance if startswith(key, "${var.aws_hostname_prefix}-rancher-")] : {
          target_group = target_group
          node = node
        }
    ]
  ])
}

# Load Balance
module "load_balancer" {
  source = "./../load_balancer"
  name = var.aws_hostname_prefix
  internal = false
  subnet_id = var.aws_subnet
  vpc_id = var.aws_vpc
  ports = local.ports
}

# Internal Load Balance
module "internal_load_balancer" {
  source = "./../load_balancer"
  name = "${var.aws_hostname_prefix}-internal"
  internal = true
  subnet_id = var.aws_subnet
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
  subnet_id = var.aws_subnet
  ssh_key_name = var.ssh_key_name
  security_group_ids = var.aws_security_group
  volume_size = var.aws_volume_size
  user_id = var.user_id
  ssh_key = var.ssh_key
  associate_public_ip = false
}

locals {
  target_groups = toset(concat(module.load_balancer.target_groups, module.internal_load_balancer.target_groups))
  target_groups_map = {
    for tg in local.target_groups : tg.name => tg
  }
}

# Route53 record
module "route53" {
  source = "./../route53"
  zone_name = var.aws_route53_zone
  record_name = var.aws_hostname_prefix
  dns_name = module.load_balancer.dns_name
}

# Internal Route53 record
module "internal_route53" {
  source = "./../route53"
  zone_name = var.aws_route53_zone
  record_name = "${var.aws_hostname_prefix}-internal"
  dns_name = module.internal_load_balancer.dns_name
}

resource "aws_lb_target_group_attachment" "attachment-server1" {
  for_each = { for entry in local.rancher_node_target_group_product: "${entry.node}.${entry.target_group}" => entry }
  target_group_arn = each.value.target_group.arn
  target_id = module.airgap_nodes[each.value.node].id
  port = each.value.target_group.port
  depends_on = [module.load_balancer, module.internal_load_balancer, module.airgap_nodes]
}
