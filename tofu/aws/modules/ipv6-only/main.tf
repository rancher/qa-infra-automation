############################################################
# Internal SSH Key
############################################################

resource "tls_private_key" "bastion_to_target_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion_to_target_key" {
  key_name   = format("%s-bastion-to-target-key", var.prefix)
  public_key = tls_private_key.bastion_to_target_key.public_key_openssh
}

resource "local_file" "bastion_to_target_private_key" {
  content         = tls_private_key.bastion_to_target_key.private_key_pem
  filename        = "${path.module}/bastion-to-target.pem"
  file_permission = "0400"
}

############################################################
# Security Groups
############################################################

resource "aws_security_group" "bastion_sg" {
  name        = format("%s-bastion-sg", var.prefix)
  description = "Allow SSH from anywhere"
  vpc_id      = var.vpc_id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = format("%s-bastion-sg", var.prefix)
  }
}

resource "aws_security_group" "server_sg" {
  name        = format("%s-rke2-server-sg", var.prefix)
  description = "Security group for RKE2 server nodes"
  vpc_id      = var.vpc_id

  # Ingress from anywhere for NLB and Rancher
  ingress {
    description = "Rancher UI HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  ingress {
    description = "Rancher UI HTTP (for Let's Encrypt)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }
  
  # Ingress from bastion for SSH
  ingress {
    description     = "SSH from Bastion"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id]
  }
  
  # Intracluster communication
  ingress {
    description = "Intra-cluster communication"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = {
    Name = format("%s-rke2-server-sg", var.prefix)
  }
}

############################################################
# Chart Downloader
############################################################

resource "null_resource" "download_rancher_chart" {
  provisioner "local-exec" {
    command = <<EOT
      set -euo pipefail
      mkdir -p ./scripts
      # Assuming a script exists to handle fetching
      # ./scripts/fetch-rancher-chart.sh "${var.rancher_chart_repo}" "${var.rancher_chart_version}"
      # mv -f "rancher-${var.rancher_chart_version}.tgz" "./scripts/rancher.tgz" 2>/dev/null
    EOT
  }
}

############################################################
# EC2 Instances
############################################################

resource "aws_instance" "bastion" {
  ami                         = "ami-03aa99ddf5498ceb9" # Ubuntu 22.04 LTS for us-east-1
  instance_type               = "t3.micro"
  subnet_id                   = var.subnet_for_bastion
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]
  key_name                    = var.existing_key_name
  associate_public_ip_address = true
  ipv6_address_count          = 1
  
  metadata_options {
    http_protocol_ipv6 = "enabled"
  }

  tags = {
    Name = format("%s-bastion", var.prefix)
  }
}

resource "aws_instance" "rke2_servers" {
  count         = var.server_count
  ami           = "ami-03aa99ddf5498ceb9" # Ubuntu 22.04 LTS for us-east-1
  instance_type = "t3.large"
  subnet_id     = var.subnet_for_rke2_servers
  vpc_security_group_ids = [aws_security_group.server_sg.id]
  key_name      = aws_key_pair.bastion_to_target_key.key_name

  ipv6_address_count = 1
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

############################################################
# Instance Provisioning
############################################################

resource "null_resource" "setup_bastion_server" {
  depends_on = [aws_instance.bastion]

  connection {
    type        = "ssh"
    host        = aws_instance.bastion.public_ip
    user        = "ubuntu"
    private_key = file(var.private_key_path)
  }

  provisioner "file" {
    source      = local_file.bastion_to_target_private_key.filename
    destination = "/home/ubuntu/bastion-to-target.pem"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 400 /home/ubuntu/bastion-to-target.pem"
    ]
  }
}

resource "null_resource" "setup_rke2_first_server" {
  depends_on = [
    aws_instance.rke2_servers[0],
    null_resource.setup_bastion_server
  ]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = aws_instance.rke2_servers[0].ipv6_addresses[0]
    private_key = tls_private_key.bastion_to_target_key.private_key_pem
    bastion_host = aws_instance.bastion.public_ip
    bastion_user = "ubuntu"
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
        "/home/ubuntu/init-server.sh '%s' '%s' '%s' '%s' '%s' '%s' '%s'",
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
}

# Add other provisioners as needed for Rancher installation

resource "null_resource" "setup_rke2_other_servers" {
  count = var.server_count - 1
  depends_on = [
    null_resource.setup_rke2_first_server
  ]

  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = aws_instance.rke2_servers[count.index + 1].ipv6_addresses[0]
    private_key = tls_private_key.bastion_to_target_key.private_key_pem
    bastion_host = aws_instance.bastion.public_ip
    bastion_user = "ubuntu"
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
        "/home/ubuntu/add-server.sh '%s' '%s' '%s' '%s' '%s' '%s' '%s' '%s'",
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

############################################################
# Network Load Balancer & DNS
############################################################

locals {
  ports = {
    http     = 80
    https    = 443
    k8s_api  = 6443
    rke2_reg = 9345
  }
}

resource "aws_lb" "lb_1" {
  name               = format("%s-nlb-ipv6", var.prefix)
  internal           = false
  load_balancer_type = "network"
  ip_address_type    = "dualstack"
  subnets            = [var.subnet_for_bastion]

  tags = {
    Name = format("%s-nlb", var.prefix)
  }
}

resource "aws_lb_target_group" "tg" {
  for_each = local.ports

  name            = format("%s-tg-%s", var.prefix, each.key)
  port            = each.value
  protocol        = "TCP"
  vpc_id          = var.vpc_id
  target_type     = "ip"
  ip_address_type = "ipv6"
}

resource "aws_lb_listener" "listener" {
  for_each = local.ports

  load_balancer_arn = aws_lb.lb_1.arn
  port              = each.value
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg[each.key].arn
  }
}

resource "aws_lb_target_group_attachment" "attachment" {
  for_each = {
    for port_key, port_val in local.ports :
    "port-${port_key}" => {
      for idx, instance in aws_instance.rke2_servers :
      "instance-${idx}" => {
        target_group_arn = aws_lb_target_group.tg[port_key].arn
        target_id        = instance.ipv6_addresses[0]
        port             = port_val
      }
    }
  }

  # This creates a flattened structure for the for_each loop
  for_each = merge(values(var.for_each)...)

  target_group_arn = each.value.target_group_arn
  target_id        = each.value.target_id
  port             = each.value.port
}

data "aws_route53_zone" "selected" {
  name         = var.route53_zone_name
  private_zone = false
}

resource "aws_route53_record" "rancher_record" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = var.rancher_hostname
  type    = "A"
  
  alias {
    name                   = aws_lb.lb_1.dns_name
    zone_id                = aws_lb.lb_1.zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "rancher_record_ipv6" {
  zone_id = data.aws_route53_zone.selected.zone_id
  name    = var.rancher_hostname
  type    = "AAAA"

  alias {
    name                   = aws_lb.lb_1.dns_name
    zone_id                = aws_lb.lb_1.zone_id
    evaluate_target_health = false
  }
}
