locals {
  elemental_nodes = {
    node1 = "elemental-node1"
  }
}

# Elemental nodes
module "elemental_nodes" {
  source = "./../compute_instance"
  for_each = local.elemental_nodes

  instance_name = "${var.gcp_hostname_prefix}-${each.value}"
  boot_image = var.boot_image
  machine_type = var.machine_type
  zone = var.zone
  network = var.network
  ssh_user = var.ssh_user
  ssh_public_key = file(var.ssh_public_key)
}