resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

# Elemental nodes
module "elemental_nodes" {
  source = "./../compute_instance"
  instance_name = "${var.gcp_hostname_prefix}-elemental-node"
  boot_image = var.boot_image
  machine_type = var.machine_type
  zone = var.zone
  network = var.network
  ssh_user = "ubuntu"
  ssh_public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_file" "private_key" {
    content  = tls_private_key.ssh.private_key_openssh
    filename = "private_key.pem"
}