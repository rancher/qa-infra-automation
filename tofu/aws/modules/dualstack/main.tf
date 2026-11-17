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
      name          = node.name == local.temp_node_names[local.first_master_index].name ? "master" : node.name
      role          = node.role
      instance_type = node.instance_type
    }
  ]
  master_node_name = local.node_names[local.first_master_index].name
  # Filter for control plane nodes
  cp_nodes = {
    for node in local.node_names : node.name => node
    if contains(node.role, "cp")
  }
  cp_node_count = length(local.cp_nodes)

  # IPv6-native nodes have no IPv4, and instance-ID targets in an IPv6 target group
  # need a primary IPv6 address, so register those nodes by IPv6 address instead.
  ipv6_native_nodes  = try(data.aws_subnet.nodes[0].ipv6_native, false)
  nlb_target_type    = local.ipv6_native_nodes ? "ip" : "instance"
  nlb_target_ip_type = local.ipv6_native_nodes ? "ipv6" : "ipv4"
  nlb_target_ids = {
    for name in keys(local.cp_nodes) : name =>
    local.ipv6_native_nodes ? aws_instance.node[name].ipv6_addresses[0] : aws_instance.node[name].id
  }

  create_bastion = var.no_of_bastion_nodes > 0

  # An IPv4-only record is useless to IPv6-only clients, and IPv6-only nodes have no public IPv4.
  publish_ipv6_record = var.enable_ipv6 && (var.kube_api_host_ipv6 || !var.enable_public_ip)
  single_cp_instance  = aws_instance.node[keys(local.cp_nodes)[0]]
  single_cp_record = (local.publish_ipv6_record
    ? try(local.single_cp_instance.ipv6_addresses[0], "")
    : coalesce(local.single_cp_instance.public_ip, local.single_cp_instance.private_ip)
  )

  # Without public IPv4 the nodes are IPv6-only and reach IPv4-only endpoints
  # through a DNS64/NAT64 resolver. See README "IPv6-only DNS".
  ipv6_only = !var.enable_public_ip && var.enable_ipv6
  # Opt out to leave the image's own resolver in place (e.g. VPC-provided DNS64).
  ipv6_manage_dns = local.ipv6_only && var.ipv6_manage_dns

  # IPv6-only hosts have no 127.0.0.1 entry to resolve their own hostname against.
  ipv6_hosts_fixup = <<-EOT
    sed -i 's/127\.0\.0\.1/::1/g' /etc/hosts
    grep -qw "$(hostname)" /etc/hosts || sed -i "s/ip6-loopback/ip6-loopback $(hostname)/" /etc/hosts
  EOT

  # IPv6-first dual-stack RKE2 binds control-plane health endpoints to ::1 while their
  # probes target "localhost"; Ubuntu maps localhost to 127.0.0.1 only.
  dualstack_hosts_fixup = <<-EOT
    grep -qE '^::1[[:space:]](.*[[:space:]])?localhost([[:space:]]|$)' /etc/hosts || echo '::1 localhost' >> /etc/hosts
  EOT

  ipv6_dns_fixup = <<-EOT
    systemctl stop systemd-resolved.service || true
    systemctl disable systemd-resolved.service || true
    rm -f /etc/resolv.conf
    cat > /etc/resolv.conf <<'RESOLVCONF'
    ${join("\n", [for resolver in var.ipv6_dns64_resolvers : "nameserver ${resolver}"])}
    RESOLVCONF
  EOT

  node_user_data = var.enable_ipv6 ? join("\n", compact([
    "#!/bin/bash",
    "set -eu",
    local.ipv6_only ? trimspace(local.ipv6_hosts_fixup) : trimspace(local.dualstack_hosts_fixup),
    local.ipv6_manage_dns ? trimspace(local.ipv6_dns_fixup) : "",
  ])) : null
}

variable "registry_ip" {
  type    = string
  default = null
}

provider "random" {}
provider "aws" {
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
  region     = var.aws_region
}

resource "random_id" "cluster_id" {
  byte_length = 6
}

resource "aws_key_pair" "ssh_public_key" {
  key_name   = "tf-key-${var.aws_hostname_prefix}-${random_id.cluster_id.hex}"
  public_key = file(var.public_ssh_key)
}

resource "aws_instance" "node" {
  for_each                    = { for node in local.node_names : node.name => node }
  ami                         = var.aws_ami
  instance_type               = each.value.instance_type != null ? each.value.instance_type : var.instance_type
  key_name                    = aws_key_pair.ssh_public_key.key_name
  vpc_security_group_ids      = var.aws_security_group
  subnet_id                   = var.aws_subnet
  associate_public_ip_address = var.enable_public_ip
  ipv6_address_count          = var.enable_ipv6 ? 1 : 0

  user_data = local.node_user_data

  ebs_block_device {
    device_name           = "/dev/sda1"
    volume_size           = var.aws_volume_size
    volume_type           = var.aws_volume_type
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "tf-${var.aws_hostname_prefix}-${each.value.name}"
  }
}

# The bastion reuses the caller-supplied security groups: those are centrally
# managed in AWS with a maintained source-CIDR allow-list for these instances.
resource "aws_instance" "bastion" {
  count                       = local.create_bastion ? 1 : 0
  ami                         = var.aws_ami
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.ssh_public_key.key_name
  vpc_security_group_ids      = var.aws_security_group
  subnet_id                   = var.aws_bastion_subnet
  associate_public_ip_address = true
  ipv6_address_count          = var.enable_ipv6 ? 1 : 0

  ebs_block_device {
    device_name           = "/dev/sda1"
    volume_size           = var.aws_volume_size
    volume_type           = var.aws_volume_type
    encrypted             = true
    delete_on_termination = true
  }

  tags = {
    Name = "tf-${var.aws_hostname_prefix}-bastion"
  }
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_80" {
  for_each         = local.cp_node_count > 1 ? local.cp_nodes : {}
  target_group_arn = aws_lb_target_group.aws_tg_80[0].arn
  target_id        = local.nlb_target_ids[each.key]
  port             = 80
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_443" {
  for_each         = local.cp_node_count > 1 ? local.cp_nodes : {}
  target_group_arn = aws_lb_target_group.aws_tg_443[0].arn
  target_id        = local.nlb_target_ids[each.key]
  port             = 443
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_9345" {
  for_each         = local.cp_node_count > 1 ? local.cp_nodes : {}
  target_group_arn = aws_lb_target_group.aws_tg_9345[0].arn
  target_id        = local.nlb_target_ids[each.key]
  port             = 9345
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_6443" {
  for_each         = local.cp_node_count > 1 ? local.cp_nodes : {}
  target_group_arn = aws_lb_target_group.aws_tg_6443[0].arn
  target_id        = local.nlb_target_ids[each.key]
  port             = 6443
}

resource "aws_lb" "aws_nlb" {
  count              = local.cp_node_count > 1 ? 1 : 0
  internal           = false
  load_balancer_type = "network"
  subnets            = [coalesce(var.aws_nlb_subnet, var.aws_subnet)]
  name               = "${var.aws_hostname_prefix}-nlb"
  # An IPv4-only NLB is unreachable from IPv6-only clients and cannot publish an AAAA record.
  ip_address_type = var.enable_ipv6 ? "dualstack" : "ipv4"

  lifecycle {
    # An IPv4 NLB cannot forward to the ipv6 target groups an IPv6-native subnet needs.
    precondition {
      condition     = !local.ipv6_native_nodes || var.enable_ipv6
      error_message = "aws_subnet is IPv6-native, so enable_ipv6 must be true for the NLB to reach the control-plane nodes."
    }
    # NLB nodes only send traffic to targets in AZs the NLB is enabled in.
    precondition {
      condition     = length(data.aws_subnet.nlb) == 0 || data.aws_subnet.nlb[0].availability_zone == data.aws_subnet.nodes[0].availability_zone
      error_message = "aws_nlb_subnet must be in the same availability zone as aws_subnet, or the control-plane targets get no traffic."
    }
  }
}

# Read only when aws_nlb_subnet is set, so existing callers need no ec2:DescribeSubnets.
data "aws_subnet" "nodes" {
  count = local.cp_node_count > 1 && var.aws_nlb_subnet != null ? 1 : 0
  id    = var.aws_subnet
}

data "aws_subnet" "nlb" {
  count = local.cp_node_count > 1 && var.aws_nlb_subnet != null ? 1 : 0
  id    = var.aws_nlb_subnet
}

resource "aws_lb_target_group" "aws_tg_80" {
  count           = local.cp_node_count > 1 ? 1 : 0
  port            = 80
  protocol        = "TCP"
  vpc_id          = var.aws_vpc
  name            = "${var.aws_hostname_prefix}-tg-80"
  target_type     = local.nlb_target_type
  ip_address_type = local.nlb_target_ip_type
  health_check {
    protocol            = "HTTP"
    port                = "traffic-port"
    path                = "/ping"
    interval            = 10
    timeout             = 6
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200-399"
  }
}

resource "aws_lb_target_group" "aws_tg_443" {
  count           = local.cp_node_count > 1 ? 1 : 0
  port            = 443
  protocol        = "TCP"
  vpc_id          = var.aws_vpc
  name            = "${var.aws_hostname_prefix}-tg-443"
  target_type     = local.nlb_target_type
  ip_address_type = local.nlb_target_ip_type
  health_check {
    protocol            = "HTTP"
    port                = 80
    path                = "/ping"
    interval            = 10
    timeout             = 6
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200-399"
  }
}

resource "aws_lb_target_group" "aws_tg_6443" {
  count           = local.cp_node_count > 1 ? 1 : 0
  port            = 6443
  protocol        = "TCP"
  vpc_id          = var.aws_vpc
  name            = "${var.aws_hostname_prefix}-tg-6443"
  target_type     = local.nlb_target_type
  ip_address_type = local.nlb_target_ip_type
  health_check {
    protocol            = "HTTP"
    port                = 80
    path                = "/ping"
    interval            = 10
    timeout             = 6
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200-399"
  }
}

resource "aws_lb_target_group" "aws_tg_9345" {
  count           = local.cp_node_count > 1 ? 1 : 0
  port            = 9345
  protocol        = "TCP"
  vpc_id          = var.aws_vpc
  name            = "${var.aws_hostname_prefix}-tg-9345"
  target_type     = local.nlb_target_type
  ip_address_type = local.nlb_target_ip_type
  health_check {
    protocol            = "HTTP"
    port                = 80
    path                = "/ping"
    interval            = 10
    timeout             = 6
    healthy_threshold   = 3
    unhealthy_threshold = 3
    matcher             = "200-399"
  }
}

resource "aws_lb_listener" "aws_nlb_listener_80" {
  count             = local.cp_node_count > 1 ? 1 : 0
  load_balancer_arn = aws_lb.aws_nlb[0].arn
  port              = "80"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aws_tg_80[0].arn
  }
}

resource "aws_lb_listener" "aws_nlb_listener_443" {
  count             = local.cp_node_count > 1 ? 1 : 0
  load_balancer_arn = aws_lb.aws_nlb[0].arn
  port              = "443"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aws_tg_443[0].arn
  }
}

resource "aws_lb_listener" "aws_nlb_listener_6443" {
  count             = local.cp_node_count > 1 ? 1 : 0
  load_balancer_arn = aws_lb.aws_nlb[0].arn
  port              = "6443"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aws_tg_6443[0].arn
  }
}

resource "aws_lb_listener" "aws_nlb_listener_9345" {
  count             = local.cp_node_count > 1 ? 1 : 0
  load_balancer_arn = aws_lb.aws_nlb[0].arn
  port              = "9345"
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aws_tg_9345[0].arn
  }
}

resource "aws_route53_record" "aws_route53" {
  zone_id         = data.aws_route53_zone.selected.zone_id
  name            = var.aws_hostname_prefix
  type            = local.cp_node_count > 1 ? "CNAME" : (local.publish_ipv6_record ? "AAAA" : "A")
  ttl             = "300"
  records         = local.cp_node_count > 1 ? [aws_lb.aws_nlb[0].dns_name] : [local.single_cp_record]
  allow_overwrite = true
}

data "aws_route53_zone" "selected" {
  name         = var.aws_route53_zone
  private_zone = false
}
