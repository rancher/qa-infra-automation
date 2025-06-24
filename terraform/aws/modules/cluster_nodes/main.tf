terraform {
  required_version = ">= 0.13.1"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.0"
    }
    ansible = {
      source  = "ansible/ansible"
      version = "1.3.0"
    }
  }
}

# Create a local variable to store the node names
locals {
  temp_node_names = flatten([
    for node_group in var.nodes : [
      for i in range(node_group.count) : {
        name = "${join("-", node_group.role)}-${i}"
        role = node_group.role
        is_server = false
      }
    ]
  ])
  first_etcd_index = index([for node in local.temp_node_names : contains(node.role, "etcd")], true)
  # Update the is_server attribute for the first etcd node
  node_names = [
    for node in local.temp_node_names : {
      name      = node.name == local.temp_node_names[local.first_etcd_index].name ? "master" : node.name
      role      = node.role
    }
  ]
  # Filter for control plane nodes
  cp_nodes = {
    for node in local.node_names : node.name => node
    if contains(node.role, "cp")
  }
  cp_node_count = length(local.cp_nodes)
}

variable "registry_ip" {
    type = string
    default = null
}

provider "random" {}
provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region =  var.aws_region
}

resource "random_id" "cluster_id" {
  byte_length       = 6
}

resource "aws_key_pair" "ssh_public_key" {
  key_name       = "tf-key-${var.user_id}-${random_id.cluster_id.hex}"
  public_key = file(var.public_ssh_key)
}

resource "aws_instance" "node" {
  for_each = { for node in local.node_names : node.name => node }
  ami = var.aws_ami
  instance_type     = var.instance_type
  key_name = aws_key_pair.ssh_public_key.key_name
  vpc_security_group_ids = var.aws_security_group
  subnet_id = var.aws_subnet
  associate_public_ip_address = var.airgap_setup || var.proxy_setup ? false : true

  ebs_block_device {
     device_name           = "/dev/sda1"
     volume_size           = var.aws_volume_size
     volume_type           = var.aws_volume_type
     encrypted             = true
     delete_on_termination = true
   }

  tags = {
    Name  = "tf-${var.user_id}-${each.value.name}"
  }
}

resource "ansible_host" "node" {
  for_each = { for node in local.node_names : node.name => node }
  name = each.value.name
  variables = {
    # Connection vars.
    ansible_user = var.aws_ssh_user
    ansible_host = aws_instance.node[each.key].public_ip
    ansible_role = join(",", each.value.role)
  }
  depends_on = [aws_instance.node]
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_80" {
  for_each = local.cp_node_count > 1 ? local.cp_nodes : {}
  target_group_arn = aws_lb_target_group.aws_tg_80[0].arn
  target_id        = aws_instance.node[each.key].id
  port             = 80
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_443" {
  for_each = local.cp_node_count > 1 ? local.cp_nodes : {}
  target_group_arn = aws_lb_target_group.aws_tg_443[0].arn
  target_id        = aws_instance.node[each.key].id
  port             = 443
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_9345" {
  for_each = local.cp_node_count > 1 ? local.cp_nodes : {}
  target_group_arn = aws_lb_target_group.aws_tg_9345[0].arn
  target_id        = aws_instance.node[each.key].id
  port             = 9345
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_6443" {
  for_each = local.cp_node_count > 1 ? local.cp_nodes : {}
  target_group_arn = aws_lb_target_group.aws_tg_6443[0].arn
  target_id        = aws_instance.node[each.key].id
  port             = 6443
}

resource "aws_lb" "aws_nlb" {
  count = local.cp_node_count  > 1 ? 1 : 0
  internal           = false
  load_balancer_type = "network"
  subnets            = [var.aws_subnet]
  name               = "${var.aws_hostname_prefix}-nlb"
}

resource "aws_lb_target_group" "aws_tg_80" {
  count = local.cp_node_count  > 1 ? 1 : 0
  port             = 80
  protocol         = "TCP"
  vpc_id           = var.aws_vpc
  name             = "${var.aws_hostname_prefix}-tg-80"
  health_check {
        protocol = "HTTP"
        port = "traffic-port"
        path = "/ping"
        interval = 10
        timeout = 6
        healthy_threshold = 3
        unhealthy_threshold = 3
        matcher = "200-399"
  }
}

resource "aws_lb_target_group" "aws_tg_443" {
  count = local.cp_node_count  > 1 ? 1 : 0
  port             = 443
  protocol         = "TCP"
  vpc_id           = var.aws_vpc
  name             = "${var.aws_hostname_prefix}-tg-443"
  health_check {
        protocol = "HTTP"
        port = 80
        path = "/ping"
        interval = 10
        timeout = 6
        healthy_threshold = 3
        unhealthy_threshold = 3
        matcher = "200-399"
  }
}

resource "aws_lb_target_group" "aws_tg_6443" {
  count = local.cp_node_count  > 1 ? 1 : 0
  port             = 6443
  protocol         = "TCP"
  vpc_id           = var.aws_vpc
  name             = "${var.aws_hostname_prefix}-tg-6443"
  health_check {
        protocol = "HTTP"
        port = 80
        path = "/ping"
        interval = 10
        timeout = 6
        healthy_threshold = 3
        unhealthy_threshold = 3
        matcher = "200-399"
  }
}

resource "aws_lb_target_group" "aws_tg_9345" {
  count = local.cp_node_count  > 1 ? 1 : 0
  port             = 9345
  protocol         = "TCP"
  vpc_id           = var.aws_vpc
  name             = "${var.aws_hostname_prefix}-tg-9345"
  health_check {
        protocol = "HTTP"
        port = 80
        path = "/ping"
        interval = 10
        timeout = 6
        healthy_threshold = 3
        unhealthy_threshold = 3
        matcher = "200-399"
  }
}

resource "aws_lb_listener" "aws_nlb_listener_80" {
  count = local.cp_node_count  > 1 ? 1 : 0
  load_balancer_arn = aws_lb.aws_nlb[0].arn
  port              = "80"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aws_tg_80[0].arn
  }
}

resource "aws_lb_listener" "aws_nlb_listener_443" {
  count = local.cp_node_count  > 1 ? 1 : 0
  load_balancer_arn = aws_lb.aws_nlb[0].arn
  port              = "443"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aws_tg_443[0].arn
  }
}

resource "aws_lb_listener" "aws_nlb_listener_6443" {
  count = local.cp_node_count  > 1 ? 1 : 0
  load_balancer_arn = aws_lb.aws_nlb[0].arn
  port              = "6443"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aws_tg_6443[0].arn
  }
}

resource "aws_lb_listener" "aws_nlb_listener_9345" {
  count = local.cp_node_count  > 1 ? 1 : 0
  load_balancer_arn = aws_lb.aws_nlb[0].arn
  port              = "9345"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aws_tg_9345[0].arn
  }
}

resource "aws_route53_record" "aws_route53" {
  zone_id            = data.aws_route53_zone.selected.zone_id
  name               = var.aws_hostname_prefix
  type    = local.cp_node_count > 1 ? "CNAME" : "A"
  ttl                = "300"
  records = local.cp_node_count > 1 ? [aws_lb.aws_nlb[0].dns_name] : [aws_instance.node[keys(local.cp_nodes)[0]].public_ip]
}

data "aws_route53_zone" "selected" {
  name               = var.aws_route53_zone
  private_zone       = false
}
