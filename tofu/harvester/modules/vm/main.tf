
# Create a local variable to store the node names
locals {
  temp_node_names = flatten([
    for node_group in var.nodes : [
      for i in range(node_group.count) : {
        name =  "${join("-", node_group.role)}-${i}"
        role = node_group.role
        is_server = false
      }
    ]
  ])
  first_etcd_index = index([for node in local.temp_node_names : contains(node.role, "etcd")], true)
  # Update the is_server attribute for the first etcd node
  node_names = [
    for node in local.temp_node_names : {
      name = node.name == local.temp_node_names[local.first_etcd_index].name ? "master" : node.name
      role = node.role
    }
  ]
  # Filter for control plane nodes
  cp_nodes = {
    for node in local.node_names : node.name => node
    if contains(node.role, "cp")
  }
  cp_node_count = length(local.cp_nodes)
}


resource "random_string" "random_suffix" {
  length  = 3
  special = false
  upper   = false
}

module "harvester_loadbalancer" {
  source = "../loadbalancer"

  create_new = var.create_loadbalancer
  generate_name = var.generate_name
  subnet_cidr = var.subnet_cidr
  gateway_ip = var.gateway_ip 
  backend_network_name = var.backend_network_name
  range_ip_end = var.range_ip_end
  range_ip_start = var.range_ip_start
  namespace = var.namespace
  ippool_name = var.ippool_name
  lookup_label_key = "${var.generate_name}-${random_string.random_suffix.result}" 
  
}

resource "harvester_ssh_key" "ssh-key" {
  name      = "${var.generate_name}-ssh-key-${random_string.random_suffix.result}"
  namespace = var.namespace

  public_key = var.ssh_key
}

resource "kubernetes_secret" "cloud-config-secret" {
  metadata {
    name      = "${var.generate_name}-secret-${random_string.random_suffix.result}"
    namespace = var.namespace
    labels = {
      "sensitive" = "false"
    }
  }
  data = {
    "userdata" = "${var.cloud_init}\nssh_authorized_keys:\n  - ${var.ssh_key}\n"
  } 
}

resource "harvester_virtualmachine" "vm" {
  for_each = { for node in local.node_names : node.name => node }
  # increase timeout to allow for updates
  timeouts {
    create = "6m"
  }
  depends_on = [
  kubernetes_secret.cloud-config-secret
  ]
  name                 = "${var.generate_name}-${each.value.name}-${random_string.random_suffix.result}"
  namespace            = var.namespace
  restart_after_update = true

  description = "Automated Terraform VM"

  tags = merge(
    {
      "ssh-user" = var.ssh_user,
      "${var.generate_name}-${random_string.random_suffix.result}" = "true"
    },
    var.labels
  )

  cpu    = var.cpu
  memory = var.mem

  efi         = true
  secure_boot = false

  run_strategy = "RerunOnFailure"
  hostname     = "${var.generate_name}-${each.value.name}-${random_string.random_suffix.result}"
  machine_type = var.machine_type

  ssh_keys = [
  harvester_ssh_key.ssh-key.id
  ]

  network_interface {
  name           = "nic-1"
  wait_for_lease = true
  model = "virtio"
  type = "bridge"
  network_name = var.network_name
  }
  
  disk {
  name       = "rootdisk"
  type       = "disk"
  size       = var.disk_size
  bus        = "virtio"
  boot_order = 1

  image       = var.image_id
  auto_delete = true
  }

  cloudinit {
  user_data_secret_name = "${var.generate_name}-secret-${random_string.random_suffix.result}"
  network_data = ""
  }
}

resource "ansible_host" "node" {
  for_each = { for node in local.node_names : node.name => node }
  name = each.value.name
  variables = {
    # Connection vars.
    ansible_user = var.ssh_user
    ansible_host = harvester_virtualmachine.vm[each.key].network_interface[0].ip_address
    ansible_role = join(",", each.value.role)

  }
  depends_on = [harvester_virtualmachine.vm]
}
