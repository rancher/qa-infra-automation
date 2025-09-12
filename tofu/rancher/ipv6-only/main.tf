terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.5.0"
    }
  }
}

############################################################
# Providers & Region
############################################################

provider "aws" {
  region = var.region
}

############################################################
# Variables
############################################################

variable "region" {
  description = "AWS region to deploy into."
  type        = string
}

# Networking (use existing VPC + subnets)
# Bastion in dual-stack public subnet, cluster nodes in IPv6-only private subnet.
variable "vpc_id" {
  description = "VPC ID where resources are placed."
  type        = string
}

variable "subnet_for_bastion" {
  description = "the AWS subnet where to create the bastion server, enables both IPv4 and IPv6 addresses"
  type        = string
}

variable "subnet_for_rke2_servers" {
  description = "the AWS subnet where to create the instances of the RKE2 cluster, enables only IPv6 addresses"
  type        = string
}

variable "existing_key_name" {
  description = "the private key for ssh to the bastion server"
  type        = string
}

variable "private_key_path" {
  description = "absolute path to the SSH private key in your local machine, used to ssh to the bastion server"
  type        = string
}

variable "server_count" {
  description = "the number of server nodes of the RKE2 cluster"
  type        = number
  default     = 3
}

variable "prefix" {
  description = "the prefix for all resources created by this module (example 'jiaqi-tf')"
  type        = string
}

variable "rke2_version" {
  description = "the k8s version of the RKE2 cluster"
  type        = string
  default     = "v1.32.5+rke2r1"
}

variable "rke2_token" {
  type    = string
  default = "auto-token-pcoep"
}

variable "rke2_cni" {
  description = "CNI for RKE2."
  type        = string
  default     = "calico"
}

# For Dual stack:
# cluster-cidr: "10.42.0.0/16,2001:cafe:42::/56"
# service-cidr: "10.43.0.0/16,2001:cafe:43::/112"
# ref: https://docs.rke2.io/networking/basic_network_options?_highlight=dual#dual-stack-configuration

variable "rke2_cluster_cidr" {
  description = "Cluster CIDR (IPv6). For dual-stack, comma-separate v4,v6."
  type        = string
  default     = "2001:cafe:42::/56"
}

variable "rke2_service_cidr" {
  description = "Service CIDR (IPv6). For dual-stack, comma-separate v4,v6."
  type        = string
  default     = "2001:cafe:43::/112"
}

variable "rancher_chart_repo" {
  description = "the chart repo"
  default     = "https://releases.rancher.com/server-charts/latest"
}

variable "cert_manager_version" {
  description = "cert-manager chart version."
  type        = string
  default     = "v1.15.3"
}

variable "cert_type" {
  description = "options: self-signed, lets-encrypt"
  default     = "self-signed"
}

variable "rancher_chart_version" {
  default = "2.12.0"
}

variable "rancher_image" {
  default = "rancher/rancher"
}

variable "rancher_image_tag" {
  default = "v2.12.0"
}

variable "let_encrypt_email" {
  default = "you@email.com"
}

variable "bootstrap_password" {
  description = "Bootstrap password for Rancher admin user"
  type        = string
}

# Create a new SSH key for bastion-to-target communication
resource "tls_private_key" "bastion_to_target_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion_to_target_key" {
  key_name   = format("%s-bastion-to-target-key", var.prefix)
  public_key = tls_private_key.bastion_to_target_key.public_key_openssh
}

# Save private key locally
resource "local_file" "bastion_to_target_private" {
  content         = tls_private_key.bastion_to_target_key.private_key_pem
  filename        = "${path.module}/bastion-to-target.pem"
  file_permission = "0400"
}

# Security group allowing SSH
resource "aws_security_group" "bastion_sg" {
  name        = format("%s-bastion-sg", var.prefix)
  description = "Allow SSH from anywhere"
  vpc_id      = var.vpc_id

  ingress {
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] # SSH from anywhere
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  tags = {
    Name = format("%s-bastion-sg", var.prefix)
  }
}

resource "aws_security_group" "server_sg_allow_all" {
  name        = format("%s-sg-allow-all", var.prefix)
  description = "Allow all inbound and outbound traffic"
  vpc_id      = var.vpc_id

  ingress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"          # -1 means all protocols
    cidr_blocks      = ["0.0.0.0/0"] # Allow all IPv4
    ipv6_cidr_blocks = ["::/0"]      # Allow all IPv6
  }

  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = format("%s-sg-allow-all", var.prefix)
  }
}

resource "null_resource" "download_rancher_chart" {
  # Run locally
  provisioner "local-exec" {
    command = <<EOT
      set -euo pipefail
      mkdir -p ./scripts
      ./scripts/fetch-rancher-chart.sh "${var.rancher_chart_repo}" "${var.rancher_chart_version}"
      mv -f "rancher-${var.rancher_chart_version}.tgz" "./scripts/rancher.tgz" 2>/dev/null
    EOT
  }
}

# Bastion instance (public IPv4)
resource "aws_instance" "bastion" {
  depends_on = [null_resource.download_rancher_chart]

  ami                    = "ami-03aa99ddf5498ceb9"
  instance_type          = "t3.micro"
  subnet_id              = var.subnet_for_bastion
  vpc_security_group_ids = [aws_security_group.bastion_sg.id]
  key_name               = var.existing_key_name

  associate_public_ip_address = true
  enable_primary_ipv6         = true
  ipv6_address_count          = 1
  metadata_options {
    http_protocol_ipv6 = "enabled"
  }

  tags = {
    Name = format("%s-bastion", var.prefix)
  }
}

# Upload the private key to Bastion & set permissions
resource "null_resource" "setup_bastion_server" {
  depends_on = [aws_instance.bastion]

  connection {
    type        = "ssh"
    host        = aws_instance.bastion.public_ip
    user        = "ubuntu"
    private_key = file(var.private_key_path)
  }

  provisioner "file" {
    source      = local_file.bastion_to_target_private.filename
    destination = "/tmp/bastion-to-target.pem"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo mv /tmp/bastion-to-target.pem /home/ubuntu/bastion-to-target.pem",
      "sudo chown ubuntu:ubuntu /home/ubuntu/bastion-to-target.pem",
      "chmod 400 /home/ubuntu/bastion-to-target.pem"
    ]
  }
}

resource "aws_instance" "rke2_servers" {
  count                  = var.server_count
  ami                    = "ami-03aa99ddf5498ceb9"
  instance_type          = "t3.large"
  subnet_id              = var.subnet_for_rke2_servers
  vpc_security_group_ids = [aws_security_group.server_sg_allow_all.id]
  key_name               = aws_key_pair.bastion_to_target_key.key_name

  # IPv6-only: no public IPv4; rely on IPv6 egress via subnet routing
  associate_public_ip_address = false
  enable_primary_ipv6         = true
  ipv6_address_count          = 1
  metadata_options {
    http_protocol_ipv6 = "enabled"
  }
  private_dns_name_options {
    enable_resource_name_dns_aaaa_record = true
  }

  root_block_device {
    volume_size = 100
  }
  tags = {
    Name = "${var.prefix}-server-${count.index + 1}"
  }
}

resource "null_resource" "setup_rke2_first_server" {
  depends_on = [
    aws_instance.rke2_servers[0],
    null_resource.setup_bastion_server
  ]

  triggers = {
    instance_id       = aws_instance.rke2_servers[0].id
    setup_script_hash = filesha256("./scripts/init-server.sh")
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = aws_instance.rke2_servers[0].ipv6_addresses[0]
    private_key = tls_private_key.bastion_to_target_key.private_key_pem

    # Use ProxyCommand to go through bastion
    bastion_host        = aws_instance.bastion.public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(var.private_key_path)
  }

  provisioner "file" {
    source      = "./scripts/init-server.sh"
    destination = "/home/ubuntu/init-server.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/init-server.sh",
      format(
        "bash -c '/home/ubuntu/init-server.sh ubuntu ubuntu %s %s %s %s %s %s %s || true'",
        var.rke2_version,
        aws_instance.rke2_servers[0].ipv6_addresses[0],
        aws_lb.lb_1.dns_name,
        var.rke2_token,
        var.rke2_cni,
        var.rke2_cluster_cidr,
        var.rke2_service_cidr
      )
    ]
  }
  # Copy Rancher charts
  provisioner "file" {
    source      = "./scripts/rancher.tgz"
    destination = "/home/ubuntu/rancher.tgz"
  }

  provisioner "file" {
    source      = "./scripts/install-rancher.sh"
    destination = "/home/ubuntu/install-rancher.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/install-rancher.sh",
      format(
        " bash -c '/home/ubuntu/install-rancher.sh %s %s %s %s %s %s %s %s %s ||  true'",
        var.rancher_chart_repo,
        var.rancher_chart_version,
        var.cert_manager_version,
        var.cert_type,
        aws_route53_record.aws_route53_record.fqdn,
        var.rancher_image,
        var.rancher_image_tag,
        var.bootstrap_password,
        var.let_encrypt_email,
      )
    ]
  }
}

resource "null_resource" "setup_rke2_other_servers" {
  count = var.server_count - 1
  depends_on = [
    aws_instance.bastion,
    null_resource.setup_rke2_first_server
  ]

  triggers = {
    instance_id = aws_instance.rke2_servers[count.index + 1].id
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = aws_instance.rke2_servers[count.index + 1].ipv6_addresses[0]
    private_key = tls_private_key.bastion_to_target_key.private_key_pem

    # Use ProxyCommand to go through bastion
    bastion_host        = aws_instance.bastion.public_ip
    bastion_user        = "ubuntu"
    bastion_private_key = file(var.private_key_path)
  }

  provisioner "file" {
    source      = "./scripts/add-server.sh"
    destination = "/home/ubuntu/add-server.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /home/ubuntu/add-server.sh",
      format(
        "bash -c '/home/ubuntu/add-server.sh %s %s %s %s %s %s %s %s' || true",
        var.rke2_version,
        aws_instance.rke2_servers[0].ipv6_addresses[0],
        aws_instance.rke2_servers[count.index + 1].ipv6_addresses[0],
        aws_lb.lb_1.dns_name,
        var.rke2_token,
        var.rke2_cni,
        var.rke2_cluster_cidr,
        var.rke2_service_cidr
      )
    ]
  }
}

locals {
  server_ipv6_map = {
    for idx, instance in aws_instance.rke2_servers :
    "server-${idx + 1}" => instance.ipv6_addresses[0]
  }
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_80_server" {
  for_each         = local.server_ipv6_map
  target_group_arn = aws_lb_target_group.aws_tg_80.arn
  target_id        = each.value
  port             = 80
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_443_server" {
  for_each         = local.server_ipv6_map
  target_group_arn = aws_lb_target_group.aws_tg_443.arn
  target_id        = each.value
  port             = 443
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_6443_server" {
  for_each         = local.server_ipv6_map
  target_group_arn = aws_lb_target_group.aws_tg_6443.arn
  target_id        = each.value
  port             = 6443
}

resource "aws_lb_target_group_attachment" "aws_tg_attachment_9345_server" {
  for_each         = local.server_ipv6_map
  target_group_arn = aws_lb_target_group.aws_tg_9345.arn
  target_id        = each.value
  port             = 9345
}

resource "aws_lb" "lb_1" {
  internal           = false
  load_balancer_type = "network"
  ip_address_type    = "dualstack"
  security_groups    = [aws_security_group.server_sg_allow_all.id]
  subnets            = [var.subnet_for_bastion]
  name               = format("%s-ipv6", var.prefix)
}

resource "aws_lb_target_group" "aws_tg_80" {
  port            = 80
  protocol        = "TCP"
  vpc_id          = var.vpc_id
  target_type     = "ip"
  ip_address_type = "ipv6"
  name            = format("%s-ipv6-tg-80", var.prefix)
  health_check {
    protocol            = "TCP"
    port                = 80
    interval            = 10
    timeout             = 6
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "aws_lb_listener_80" {
  load_balancer_arn = aws_lb.lb_1.arn
  port              = 80
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aws_tg_80.arn
  }
}

resource "aws_lb_target_group" "aws_tg_443" {
  port            = 443
  protocol        = "TCP"
  vpc_id          = var.vpc_id
  target_type     = "ip"
  ip_address_type = "ipv6"
  name            = format("%s-ipv6-tg-443", var.prefix)
  health_check {
    protocol            = "TCP"
    port                = 443
    interval            = 10
    timeout             = 6
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "aws_lb_listener_443" {
  load_balancer_arn = aws_lb.lb_1.arn
  port              = 443
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aws_tg_443.arn
  }
}

resource "aws_lb_target_group" "aws_tg_6443" {
  port            = 6443
  protocol        = "TCP"
  vpc_id          = var.vpc_id
  target_type     = "ip"
  ip_address_type = "ipv6"
  name            = format("%s-ipv6-tg-6443", var.prefix)
  health_check {
    protocol            = "TCP"
    port                = 6443
    interval            = 10
    timeout             = 6
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "aws_lb_listener_6443" {
  load_balancer_arn = aws_lb.lb_1.arn
  port              = 6443
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aws_tg_6443.arn
  }
}

resource "aws_lb_target_group" "aws_tg_9345" {
  port            = 9345
  protocol        = "TCP"
  vpc_id          = var.vpc_id
  target_type     = "ip"
  ip_address_type = "ipv6"
  name            = format("%s-ipv6-tg-9345", var.prefix)
  health_check {
    protocol            = "TCP"
    port                = 9345
    interval            = 10
    timeout             = 6
    healthy_threshold   = 3
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "aws_lb_listener_9345" {
  load_balancer_arn = aws_lb.lb_1.arn
  port              = 9345
  protocol          = "TCP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.aws_tg_9345.arn
  }
}

resource "aws_route53_record" "aws_route53_record" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = format("%s-ipv6", var.prefix)
  type    = "CNAME"
  ttl     = 300
  records = [aws_lb.lb_1.dns_name]
}

data "aws_route53_zone" "selected" {
  name         = "test.rancher.space"
  private_zone = false
}

output "coredns_patch_instruction" {
  value = <<EOT
Please patch the rke2-coredns-rke2-coredns ConfigMap in the kube-system namespace:
  kubectl -n kube-system edit cm rke2-coredns-rke2-coredns

Change the line:
  name         = "test.rancher.space"
to:
  forward  . 2001:4860:4860::8888

You can use the following command:

kubectl -n kube-system get cm rke2-coredns-rke2-coredns -o json  \
| jq '.data.Corefile |= sub("forward\\s+\\.\\s+/etc/resolv\\.conf"; "forward  . 2001:4860:4860::8888")' \
| kubectl apply -f -

Coredns will reload the config shortly.

Or restart CoreDNS:
  kubectl -n kube-system delete pod -l k8s-app=kube-dns
EOT
}


output "rancher_server_url" {
  value = <<EOT
Rancher has been successfully deployed!

You can now access the Rancher UI at:
  https://${aws_route53_record.aws_route53_record.fqdn}

Use the bootstrap password you provided in 'bootstrap_password' to log in as the default 'admin' user.

EOT
}

