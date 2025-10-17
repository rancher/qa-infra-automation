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
}

# Load Balance
module "load_balancer" {
  count = can(var.node_groups["rancher"]) ? 1 : 0
  source = "./../load_balancer"
  name = var.aws_hostname_prefix
  internal = false
  subnet_id = var.aws_subnet
  vpc_id = var.aws_vpc
  ports = local.ports
}

# Internal Load Balance
module "internal_load_balancer" {
  count = can(var.node_groups["rancher"]) ? 1 : 0
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
