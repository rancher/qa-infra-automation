resource "harvester_image" "elemental" {
  name      = "elemental"
  namespace = var.image_namespace

  display_name = "elemental.iso"
  source_type  = "download"
  url          = var.image_url
}

resource "harvester_virtualmachine" "elemental-vm" {
  count     = 3
  name      = "elemental-vm-${count.index}"
  namespace = var.namespace

  depends_on = [
    harvester_image.elemental
  ]

  cpu    = var.cpu
  memory = var.memory

  disk {
    name       = "cdrom-disk"
    type       = "cd-rom"
    size       = "2Gi"
    bus        = "sata"
    boot_order = 2

    image       = harvester_image.elemental.id
    auto_delete = true
  }

  disk {
    name       = "rootdisk"
    type       = "disk"
    size       = var.disk_size
    bus        = "virtio"
    boot_order = 1
    auto_delete = true
  }

  network_interface {
    name         = "default"
    model        = "virtio"
    type         = "bridge"
  }

  run_strategy    = "RerunOnFailure"

  cloudinit {
    user_data_base64 = var.user_data_base64
  }

  efi         = true
  secure_boot = true
  
  tpm {}
}