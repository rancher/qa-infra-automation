
# Create a local variable to store the node names
locals {
  temp_node_names = flatten([
    for node_group in var.nodes : [
      for i in range(node_group.count) : {
        name =  "${var.hostname_prefix}-${join("-", node_group.role)}-${i}"
        role = node_group.role
        is_server = false
      }
    ]
  ])
  first_etcd_index = index([for node in local.temp_node_names : contains(node.role, "etcd")], true)
  # Update the is_server attribute for the first etcd node
  node_names = [
    for node in local.temp_node_names : {
      name = node.name == local.temp_node_names[local.first_etcd_index].name ? "${var.hostname_prefix}-master" : node.name
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

resource "harvester_ssh_key" "ssh-key" {
  name      = "${var.hostname_prefix}-ssh-key-${random_string.random_suffix.result}"
  namespace = var.namespace

  public_key = var.ssh_key
}

locals {
  cloud_init = <<-EOT
    #cloud-config
    package_update: true
    packages:
      - qemu-guest-agent
    runcmd:
      - - systemctl
        - enable
        - --now
        - qemu-guest-agent.service
    ssh_authorized_keys:
      - ${var.ssh_key}
    EOT
}

resource "kubernetes_secret" "cloud-config-secret" {
  metadata {
    name      = "${var.hostname_prefix}-secret-${random_string.random_suffix.result}"
    namespace = var.namespace
    labels = {
      "sensitive" = "false"
    }
  }
  data = {
    "userdata" = local.cloud_init
  } 
}


resource "harvester_virtualmachine" "vm" {

  for_each = { for node in local.node_names : node.name => node }
  depends_on = [
  kubernetes_secret.cloud-config-secret
  ]
  name                 = "${each.value.name}"
  namespace            = var.namespace
  restart_after_update = true

  description = "Automated VM"
  tags = {
  ssh-user = var.ssh_user
  }

  cpu    = var.cpu
  memory = var.mem

  efi         = true
  secure_boot = false

  run_strategy = "RerunOnFailure"
  hostname     = "${each.value.name}"
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
  user_data_secret_name = "${var.hostname_prefix}-secret-${random_string.random_suffix.result}"
  network_data = ""
  }
}
