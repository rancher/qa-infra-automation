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
  network = var.network
  zone = var.zone
  startup_script = "export DOWNLOAD_URL=${var.download_url} && ${file("./init-node.sh")}"
}