output "fqdn" {
  value = aws_route53_record.aws_route53.fqdn
}

output "kube_api_host" {
  value       = aws_instance.node[local.node_names[local.first_etcd_index].name].public_ip
  description = "The public IP address of the first etcd node, or 'No etcd node found'."
}

output "instance_public_ips" {
  description = "The public IP addresses assigned to the EC2 instances"
  value       = [for instance in aws_instance.node : instance.public_ip]
}

# Categorize nodes for Ansible inventory generation
locals {
  # Master node (first etcd node, renamed to "master")
  master_node = {
    name  = local.node_names[local.first_etcd_index].name
    ip    = aws_instance.node[local.node_names[local.first_etcd_index].name].public_ip
    roles = join(",", local.node_names[local.first_etcd_index].role)
  }

  # Server nodes (nodes with "cp" or "etcd" role, excluding master)
  server_nodes = [
    for node in local.node_names : {
      name  = node.name
      ip    = aws_instance.node[node.name].public_ip
      roles = join(",", node.role)
    }
    if node.name != local.node_names[local.first_etcd_index].name && (contains(node.role, "cp") || contains(node.role, "etcd"))
  ]

  # Worker nodes (nodes with "worker" role, but NOT cp or etcd)
  worker_nodes = [
    for node in local.node_names : {
      name  = node.name
      ip    = aws_instance.node[node.name].public_ip
      roles = join(",", node.role)
    }
    if contains(node.role, "worker") && !contains(node.role, "cp") && !contains(node.role, "etcd")
  ]

  # All etcd nodes for group membership
  etcd_nodes = [
    for node in local.node_names : {
      name  = node.name
      ip    = aws_instance.node[node.name].public_ip
      roles = join(",", node.role)
    }
    if contains(node.role, "etcd")
  ]

  # All control plane nodes for group membership
  cp_nodes_list = [
    for node in local.node_names : {
      name  = node.name
      ip    = aws_instance.node[node.name].public_ip
      roles = join(",", node.role)
    }
    if contains(node.role, "cp")
  ]

  # Generate inventory YAML content using template
  ansible_inventory_content = templatefile("${path.module}/templates/inventory.yaml.tftpl", {
    master_node    = local.master_node
    server_nodes   = local.server_nodes
    worker_nodes   = local.worker_nodes
    etcd_nodes     = local.etcd_nodes
    cp_nodes       = local.cp_nodes_list
    fqdn           = aws_route53_record.aws_route53.fqdn
    kube_api_host  = aws_instance.node[local.node_names[local.first_etcd_index].name].public_ip
    ssh_user       = var.aws_ssh_user
    private_ssh_key = var.private_ssh_key
  })
}

# Write generated inventory to file
# inventory_output_path lets callers (e.g. Makefile) direct the file to the
# appropriate ansible/<distro>/<env>/ directory. Falls back to the module
# directory when run standalone.
locals {
  inventory_path = var.inventory_output_path != "" ? var.inventory_output_path : "${path.module}/inventory.yml"
}

resource "local_file" "ansible_inventory" {
  content         = local.ansible_inventory_content
  filename        = local.inventory_path
  file_permission = "0644"
}

# Output the generated inventory content for reference
output "ansible_inventory_yaml" {
  description = "Generated Ansible inventory in YAML format"
  value       = local.ansible_inventory_content
}