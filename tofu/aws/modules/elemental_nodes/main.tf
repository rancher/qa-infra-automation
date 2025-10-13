locals {
  elemental_nodes = {
    node1 = "elemental_node1"
    node2 = "elemental_node2"
    node3 = "elemental_node3"
  }
}

# Elemental nodes
module "elemental_nodes" {
  source = "./../ec2_instance"
  for_each = local.elemental_nodes

  name = "${var.aws_hostname_prefix}-${each.value}"
  ami = var.ami
  instance_type = var.instance_type
  subnet_id = var.aws_subnet
  ssh_key_name = var.ssh_key_name
  security_group_ids = var.aws_security_group
  volume_size = 100
  user_id = var.user_id
  ssh_key = var.ssh_key
  associate_public_ip = true
}

resource "null_resource" "elemental_node_provisioning" {
  for_each = local.elemental_nodes

  depends_on = [module.elemental_nodes]

  triggers = {
    public_dns  = module.elemental_nodes[each.key].public_dns
  }

  connection {
    type        = "ssh"
    host        = module.elemental_nodes[each.key].public_dns
    user        = "ubuntu"
    private_key = file(var.ssh_key)
  }

  provisioner "file" {
    source      = var.elemental_iso
    destination = "/tmp/elemental.iso"
  }

  provisioner "remote-exec" {
    script = "./init-node.sh"
  }    
}