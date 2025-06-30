terraform {
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

provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

resource "aws_instance" "rke2_bastion" {
  ami                    = var.aws_ami
  instance_type          = var.instance_type
  subnet_id              = var.aws_subnet
  vpc_security_group_ids = []
  key_name               = var.ssh_key_name

  root_block_device {
    volume_size = var.aws_volume_size
  }

  tags = {
    Name = "${var.aws_hostname_prefix}-rke2_bastion"
  }

  connection {
    type        = "ssh"
    user        = var.user_id
    host        = self.public_ip
    private_key = file(var.ssh_key)
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = ["echo Connected!!!"]
  }
}

resource "aws_instance" "registry" {
  ami                    = var.aws_ami
  instance_type          = var.instance_type
  subnet_id              = var.aws_subnet
  vpc_security_group_ids = []
  key_name               = var.ssh_key_name

  root_block_device {
    volume_size = var.aws_volume_size
  }

  tags = {
    Name = "${var.aws_hostname_prefix}-registry"
  }

  connection {
    type        = "ssh"
    user        = var.user_id
    host        = self.public_ip
    private_key = file(var.ssh_key)
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = ["echo Connected!!!"]
  }
}

resource "aws_instance" "rke2_server1" {
  associate_public_ip_address = false
  ami                         = var.aws_ami
  instance_type               = var.instance_type
  subnet_id                   = var.aws_subnet
  vpc_security_group_ids      = []
  key_name                    = var.ssh_key_name

  root_block_device {
    volume_size = var.aws_volume_size
  }

  tags = {
    Name = "${var.aws_hostname_prefix}-rke2_server1"
  }

  connection {
    type        = "ssh"
    user        = var.user_id
    host        = self.private_ip
    private_key = file(var.ssh_key)
    timeout     = "5m"
  }
}

resource "aws_instance" "rke2_server2" {
  associate_public_ip_address = false
  ami                         = var.aws_ami
  instance_type               = var.instance_type
  subnet_id                   = var.aws_subnet
  vpc_security_group_ids      = []
  key_name                    = var.ssh_key_name

  root_block_device {
    volume_size = var.aws_volume_size
  }

  tags = {
    Name = "${var.aws_hostname_prefix}-rke2_server2"
  }

  connection {
    type        = "ssh"
    user        = var.user_id
    host        = self.private_ip
    private_key = file(var.ssh_key)
    timeout     = "5m"
  }
}

resource "aws_instance" "rke2_server3" {
  associate_public_ip_address = false
  ami                         = var.aws_ami
  instance_type               = var.instance_type
  subnet_id                   = var.aws_subnet
  vpc_security_group_ids      = []
  key_name                    = var.ssh_key_name

  root_block_device {
    volume_size = var.aws_volume_size
  }

  tags = {
    Name = "${var.aws_hostname_prefix}-rke2_server3"
  }

  connection {
    type        = "ssh"
    user        = var.user_id
    host        = self.private_ip
    private_key = file(var.ssh_key)
    timeout     = "5m"
  }
}

locals {
  rke2_instance_ids = {
    rke2_server3 = aws_instance.rke2_server3.id
    rke2_server1 = aws_instance.rke2_server1.id
    rke2_server2 = aws_instance.rke2_server2.id
  }
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_80_server" {
  for_each         = local.rke2_instance_ids
  target_group_arn = aws_lb_target_group.aws_tg_80.arn
  target_id        = each.value
  port             = 80
}

resource "aws_lb_target_group_attachment" "aws_internal_tg_attachment_80_server" {
  for_each         = local.rke2_instance_ids
  target_group_arn = aws_lb_target_group.aws_internal_tg_80.arn
  target_id        = each.value
  port             = 80
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_443_server" {
  for_each         = local.rke2_instance_ids
  target_group_arn = aws_lb_target_group.aws_tg_443.arn
  target_id        = each.value
  port             = 443
}

resource "aws_lb_target_group_attachment" "aws_internal_tg_attachment_443_server" {
  for_each         = local.rke2_instance_ids
  target_group_arn = aws_lb_target_group.aws_internal_tg_443.arn
  target_id        = each.value
  port             = 443
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_6443_server" {
  for_each         = local.rke2_instance_ids
  target_group_arn = aws_lb_target_group.aws_tg_6443.arn
  target_id        = each.value
  port             = 6443
}

resource "aws_lb_target_group_attachment" "aws_internal_tg_attachment_6443_server" {
  for_each         = local.rke2_instance_ids
  target_group_arn = aws_lb_target_group.aws_internal_tg_6443.arn
  target_id        = each.value
  port             = 6443
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_9345_server" {
  for_each         = local.rke2_instance_ids
  target_group_arn = aws_lb_target_group.aws_tg_9345.arn
  target_id        = each.value
  port             = 9345
}

resource "aws_lb_target_group_attachment" "aws_internal_tg_attachment_9345_server" {
  for_each         = local.rke2_instance_ids
  target_group_arn = aws_lb_target_group.aws_internal_tg_9345.arn
  target_id        = each.value
  port             = 9345
}

resource "aws_lb" "aws_lb" {
  internal           = false
  load_balancer_type = "network"
  subnets            = [var.aws_subnet]
  name               = var.aws_hostname_prefix
}

resource "aws_lb" "aws_internal_lb" {
  internal           = true
  load_balancer_type = "network"
  subnets            = [var.aws_subnet]
  name               = "${var.aws_hostname_prefix}-internal"
}

resource "aws_lb_target_group" "aws_tg_80" {
  port     = 80
  protocol = "TCP"
  vpc_id   = var.aws_vpc
  name     = "${var.aws_hostname_prefix}-tg-80"
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

resource "aws_lb_target_group" "aws_internal_tg_80" {
  port     = 80
  protocol = "TCP"
  vpc_id   = var.aws_vpc
  name     = "${var.aws_hostname_prefix}-internal-tg-80"
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

resource "aws_lb_listener" "aws_lb_listener_80" {
  load_balancer_arn = aws_lb.aws_lb.arn
  port              = 80
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aws_tg_80.arn
  }
}

resource "aws_lb_listener" "aws_internal_lb_listener_80" {
  load_balancer_arn = aws_lb.aws_internal_lb.arn
  port              = 80
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aws_internal_tg_80.arn
  }
}

resource "aws_lb_target_group" "aws_tg_443" {
  port     = 443
  protocol = "TCP"
  vpc_id   = var.aws_vpc
  name     = "${var.aws_hostname_prefix}-tg-443"
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

resource "aws_lb_target_group" "aws_internal_tg_443" {
  port     = 443
  protocol = "TCP"
  vpc_id   = var.aws_vpc
  name     = "${var.aws_hostname_prefix}-internal-tg-443"
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

resource "aws_lb_listener" "aws_lb_listener_443" {
  load_balancer_arn = aws_lb.aws_lb.arn
  port              = 443
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aws_tg_443.arn
  }
}

resource "aws_lb_listener" "aws_internal_lb_listener_443" {
  load_balancer_arn = aws_lb.aws_internal_lb.arn
  port              = 443
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aws_internal_tg_443.arn
  }
}

resource "aws_lb_target_group" "aws_tg_6443" {
  port     = 6443
  protocol = "TCP"
  vpc_id   = var.aws_vpc
  name     = "${var.aws_hostname_prefix}-tg-6443"
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

resource "aws_lb_target_group" "aws_internal_tg_6443" {
  port     = 6443
  protocol = "TCP"
  vpc_id   = var.aws_vpc
  name     = "${var.aws_hostname_prefix}-internal-tg-6443"
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

resource "aws_lb_listener" "aws_lb_listener_6443" {
  load_balancer_arn = aws_lb.aws_lb.arn
  port              = 6443
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aws_tg_6443.arn
  }
}

resource "aws_lb_listener" "aws_internal_lb_listener_6443" {
  load_balancer_arn = aws_lb.aws_internal_lb.arn
  port              = 6443
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aws_internal_tg_6443.arn
  }
}

resource "aws_lb_target_group" "aws_tg_9345" {
  port     = 9345
  protocol = "TCP"
  vpc_id   = var.aws_vpc
  name     = "${var.aws_hostname_prefix}-tg-9345"
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

resource "aws_lb_target_group" "aws_internal_tg_9345" {
  port     = 9345
  protocol = "TCP"
  vpc_id   = var.aws_vpc
  name     = "${var.aws_hostname_prefix}-internal-tg-9345"
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

resource "aws_lb_listener" "aws_lb_listener_9345" {
  load_balancer_arn = aws_lb.aws_lb.arn
  port              = 9345
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aws_tg_9345.arn
  }
}

resource "aws_lb_listener" "aws_internal_lb_listener_9345" {
  load_balancer_arn = aws_lb.aws_internal_lb.arn
  port              = 9345
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aws_internal_tg_9345.arn
  }
}

resource "aws_route53_record" "aws_route53_record" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = var.aws_hostname_prefix
  type    = "CNAME"
  ttl     = 300
  records = [aws_lb.aws_lb.dns_name]
}

data "aws_route53_zone" "selected" {
  name         = "qa.rancher.space"
  private_zone = false
}

resource "aws_route53_record" "aws_internal_route53_record" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = "${var.aws_hostname_prefix}-internal"
  type    = "CNAME"
  ttl     = 300
  records = [aws_lb.aws_internal_lb.dns_name]
}

