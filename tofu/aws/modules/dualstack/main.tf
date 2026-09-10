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
  first_etcd_index = index([for node in local.temp_node_names : contains(node.role, "etcd")], true)
  # Update the is_server attribute for the first etcd node
  node_names = [
    for idx, node in local.temp_node_names : {
      name = node.name == local.temp_node_names[local.first_etcd_index].name ? "master" : node.name
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

resource "aws_instance" "node" {
  for_each = { for node in local.node_names : node.name => node }
  ami = var.aws_ami
  instance_type = each.value.instance_type != null ? each.value.instance_type : var.instance_type
  key_name = aws_key_pair.ssh_public_key.key_name
  vpc_security_group_ids = var.aws_security_group
  subnet_id = var.aws_subnet
  associate_public_ip_address = var.enable_public_ip ? true : false
  ipv6_address_count          = var.enable_ipv6 ? 1 : 0

  user_data = var.enable_public_ip ? null : <<-EOT
    #!/bin/bash
    echo "Stopping systemd-resolved"
    systemctl stop systemd-resolved.service || true
    echo "Updating /etc/hosts"
    instance_id=$(curl -s http://169.254.169.254/latest/meta-data/instance-id || hostname)
    sed -i -e 's/127.0.0.1/::1/g' -e "s/ip6-loopback/ip6-loopback $instance_id/g" /etc/hosts
    echo "Updating /etc/resolv.conf"
    sed -i 's/127.0.0.53/2a00:1098:2c::1/g' /etc/resolv.conf
  EOT

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

resource "aws_instance" "bastion" {
  ami                         = var.aws_ami
  instance_type               = var.instance_type
  key_name                    = aws_key_pair.ssh_public_key.key_name
  vpc_security_group_ids      = var.aws_security_group
  subnet_id                   = var.aws_bastion_subnet
  associate_public_ip_address = true
  ipv6_address_count          = var.enable_ipv6 ? 1 : 0
  count                       = var.no_of_bastion_nodes == 0 ? 0 : 1
  
  connection {
    type          = "ssh"
    user          = var.aws_ssh_user
    host          = self.public_ip
    private_key   = file(var.private_ssh_key)
  }

  ebs_block_device {
     device_name = "/dev/sda1"
     volume_size = var.aws_volume_size
     volume_type = var.aws_volume_type
     encrypted = true
     delete_on_termination = true
   }

  tags = {
    Name = "tf-${var.aws_hostname_prefix}-bastion"
  }
  
  provisioner "file" {
    source = var.private_ssh_key
    destination = "/tmp/${var.key_name}.pem"
  }

  provisioner "file" {
    source = "scripts/bastion_prepare.sh"
    destination = "/tmp/bastion_prepare.sh"
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
  subnets = [var.aws_subnet]
  name = "${var.aws_hostname_prefix}-nlb"
}

resource "aws_lb_target_group" "aws_tg_80" {
  count = local.cp_node_count  > 1 ? 1 : 0
  port = 80
  protocol = "TCP"
  vpc_id = var.aws_vpc
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
  vpc_id = var.aws_vpc
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
  vpc_id = var.aws_vpc
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
  vpc_id = var.aws_vpc
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
  type = local.cp_node_count > 1 ? "CNAME" : (coalesce(aws_instance.node[keys(local.cp_nodes)[0]].public_ip, aws_instance.node[keys(local.cp_nodes)[0]].private_ip, "ipv6") == "ipv6" ? "AAAA" : "A")
  ttl = "300"
  records = local.cp_node_count > 1 ? [aws_lb.aws_nlb[0].dns_name] : [coalesce(aws_instance.node[keys(local.cp_nodes)[0]].public_ip, aws_instance.node[keys(local.cp_nodes)[0]].private_ip, try(aws_instance.node[keys(local.cp_nodes)[0]].ipv6_addresses[0], ""))]
}

data "aws_route53_zone" "selected" {
  name = var.aws_route53_zone
  private_zone = false
}

resource "null_resource" "prepare_bastion" {
  depends_on = [ aws_instance.bastion ]
  connection {
    type          = "ssh"
    user          = var.aws_ssh_user
    host          = aws_instance.bastion[0].public_ip
    private_key   = file(var.private_ssh_key)
  }

  provisioner "remote-exec" {
    inline = [<<-EOT
      sudo cp /tmp/${var.key_name}.pem /tmp/*.sh /tmp/*.ps1 ~/
      sudo cp -r /tmp/basic-registry ~/
      sudo chmod +x bastion_prepare.sh
      sudo ./bastion_prepare.sh
    EOT
    ]
  }
}
