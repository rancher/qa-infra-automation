# Create a local variable to store the node names
locals {
  temp_node_names = flatten([
    for node_group in var.nodes : [
      for i in range(node_group.count) : {
        name          = "${join("-", node_group.role)}-${i}"
        role          = node_group.role
        is_server     = false
        instance_type = node_group.instance_type
      }
    ]
  ])
  # Master = first etcd, fall back to first cp (cp-only + external datastore). try() avoids index() errors when role absent.
  first_etcd_index   = try(index([for node in local.temp_node_names : contains(node.role, "etcd")], true), -1)
  first_cp_index     = try(index([for node in local.temp_node_names : contains(node.role, "cp")], true), -1)
  first_master_index = local.first_etcd_index >= 0 ? local.first_etcd_index : local.first_cp_index
  node_names = [
    for idx, node in local.temp_node_names : {
      name = node.name == local.temp_node_names[local.first_master_index].name ? "master" : node.name
      role = node.role
      instance_type = node.instance_type
    }
  ]
  # Filter for control plane nodes
  cp_nodes = {
    for node in local.node_names : node.name => node
    if contains(node.role, "cp")
  }
  cp_node_count = length(local.cp_nodes)

  vpc_id         = var.aws_vpc
  subnet_id      = var.aws_subnet
  vpc_cidr_block = data.aws_vpc.selected.cidr_block

  # Self-provision the main security group the same way when none is supplied.
  create_security_group = length(var.aws_security_group) == 0
  security_group_ids    = local.create_security_group ? [aws_security_group.ephemeral[0].id] : var.aws_security_group
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
  byte_length = 6
}

resource "aws_key_pair" "ssh_public_key" {
  key_name = "tf-key-${var.aws_hostname_prefix}-${random_id.cluster_id.hex}"
  public_key = file(var.public_ssh_key)
}

# Main security group, self-provisioned when var.aws_security_group is empty.
# intra-group traffic, and the RKE2/Rancher NLB listener ports.
resource "aws_security_group" "ephemeral" {
  count       = local.create_security_group ? 1 : 0
  name        = "tf-${var.aws_hostname_prefix}-sg"
  description = "Ephemeral security group for ${var.aws_hostname_prefix} (created because var.aws_security_group was empty)"
  vpc_id      = local.vpc_id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "All traffic between instances in this security group"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  dynamic "ingress" {
    for_each = toset(["80", "443", "6443", "9345"])
    content {
      description = "RKE2/Rancher NLB listener ${ingress.value}"
      from_port   = tonumber(ingress.value)
      to_port     = tonumber(ingress.value)
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    description = "Allow all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tf-${var.aws_hostname_prefix}-sg"
  }
}


# Dedicated SSH security group with stable CIDR rules.
#
# Why this exists: when SSH access for the jumpbox/bastion is granted ONLY via a
# managed prefix list (e.g. a churning "QA public IPs" list), AWS propagates the
# prefix-list entries to each new instance's ENI asynchronously. On freshly
# launched instances one ENI can lag or land on a stale list version and silently
# drop the jumpbox's SSH SYN to that node until propagation catches up - so one
# random node per build looks "unreachable" for minutes. Plain CIDR SG rules, by
# contrast, are realized on the ENI immediately at launch, so SSH from the
# jumpbox always works.
#
# This SG is attached ALONGSIDE var.aws_security_group (AWS SGs are additive: a
# flow is allowed if ANY attached SG allows it), so the existing RKE2/Rancher
# port matrix in the shared SG is left untouched.
resource "aws_security_group" "ssh" {
  count       = var.create_ssh_security_group ? 1 : 0
  name        = "tf-${var.aws_hostname_prefix}-ssh"
  description = "Stable SSH (22) access for ${var.aws_hostname_prefix} (avoids prefix-list propagation lag)."
  vpc_id      = local.vpc_id

  dynamic "ingress" {
    for_each = length(var.ssh_allowed_cidrs) > 0 ? [1] : []
    content {
      description = "SSH from stable CIDRs (jumpbox/bastion/office)"
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = var.ssh_allowed_cidrs
    }
  }

  ingress {
    description = "SSH from within the VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [local.vpc_cidr_block]
  }

  egress {
    description = "Allow all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "tf-${var.aws_hostname_prefix}-ssh"
  }
}

resource "aws_instance" "node" {
  for_each = { for node in local.node_names : node.name => node }
  ami = var.aws_ami
  instance_type = each.value.instance_type != null ? each.value.instance_type : var.instance_type
  key_name = aws_key_pair.ssh_public_key.key_name
  vpc_security_group_ids = compact(concat(local.security_group_ids, var.create_ssh_security_group ? [aws_security_group.ssh[0].id] : []))
  subnet_id = local.subnet_id
  associate_public_ip_address = var.airgap_setup || var.proxy_setup ? false : true

  ebs_block_device {
     device_name = "/dev/sda1"
     volume_size = var.aws_volume_size
     volume_type = var.aws_volume_type
     encrypted = true
     delete_on_termination = true
   }

  tags = {
    Name = "tf-${var.aws_hostname_prefix}-${each.value.name}"
  }
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_80" {
  for_each = local.cp_node_count > 1 ? local.cp_nodes : {}
  target_group_arn = aws_lb_target_group.aws_tg_80[0].arn
  target_id = aws_instance.node[each.key].id
  port = 80
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_443" {
  for_each = local.cp_node_count > 1 ? local.cp_nodes : {}
  target_group_arn = aws_lb_target_group.aws_tg_443[0].arn
  target_id = aws_instance.node[each.key].id
  port = 443
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_9345" {
  for_each = local.cp_node_count > 1 ? local.cp_nodes : {}
  target_group_arn = aws_lb_target_group.aws_tg_9345[0].arn
  target_id = aws_instance.node[each.key].id
  port = 9345
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_6443" {
  for_each = local.cp_node_count > 1 ? local.cp_nodes : {}
  target_group_arn = aws_lb_target_group.aws_tg_6443[0].arn
  target_id = aws_instance.node[each.key].id
  port = 6443
}

resource "aws_lb" "aws_nlb" {
  count = local.cp_node_count  > 1 ? 1 : 0
  internal = false
  load_balancer_type = "network"
  subnets = [local.subnet_id]
  name = "${var.aws_hostname_prefix}-nlb"
}

resource "aws_lb_target_group" "aws_tg_80" {
  count = local.cp_node_count  > 1 ? 1 : 0
  port = 80
  protocol = "TCP"
  vpc_id = local.vpc_id
  name = "${var.aws_hostname_prefix}-tg-80"
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
  port = 443
  protocol = "TCP"
  vpc_id = local.vpc_id
  name = "${var.aws_hostname_prefix}-tg-443"
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
  port = 6443
  protocol = "TCP"
  vpc_id = local.vpc_id
  name = "${var.aws_hostname_prefix}-tg-6443"
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
  port = 9345
  protocol = "TCP"
  vpc_id = local.vpc_id
  name = "${var.aws_hostname_prefix}-tg-9345"
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
  port = "80"
  protocol = "TCP"
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.aws_tg_80[0].arn
  }
}

resource "aws_lb_listener" "aws_nlb_listener_443" {
  count = local.cp_node_count  > 1 ? 1 : 0
  load_balancer_arn = aws_lb.aws_nlb[0].arn
  port = "443"
  protocol = "TCP"
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.aws_tg_443[0].arn
  }
}

resource "aws_lb_listener" "aws_nlb_listener_6443" {
  count = local.cp_node_count  > 1 ? 1 : 0
  load_balancer_arn = aws_lb.aws_nlb[0].arn
  port = "6443"
  protocol = "TCP"
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.aws_tg_6443[0].arn
  }
}

resource "aws_lb_listener" "aws_nlb_listener_9345" {
  count = local.cp_node_count  > 1 ? 1 : 0
  load_balancer_arn = aws_lb.aws_nlb[0].arn
  port = "9345"
  protocol = "TCP"
  default_action {
    type = "forward"
    target_group_arn = aws_lb_target_group.aws_tg_9345[0].arn
  }
}

resource "aws_route53_record" "aws_route53" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name = var.aws_hostname_prefix
  type = local.cp_node_count > 1 ? "CNAME" : "A"
  ttl = "300"
  records = local.cp_node_count > 1 ? [aws_lb.aws_nlb[0].dns_name] : [aws_instance.node[keys(local.cp_nodes)[0]].public_ip]
}

data "aws_route53_zone" "selected" {
  name = var.aws_route53_zone
  private_zone = false
}

# Used to auto-allow SSH from the VPC's own CIDR in the dedicated SSH SG above.
data "aws_vpc" "selected" {
  id = var.aws_vpc
}
