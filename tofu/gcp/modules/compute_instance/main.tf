resource "google_compute_instance" "this" {
  boot_disk {
    auto_delete = true

    initialize_params {
      image = var.boot_image
      size  = 100
      type  = "pd-standard"
    }

    mode = "READ_WRITE"
  }

  can_ip_forward      = true
  deletion_protection = false
  enable_display      = false

  labels = {
    goog-ec-src = "vm_add-tf"
  }

  machine_type = var.machine_type
  name         = var.instance_name

  network_interface {
    access_config {}

    queue_count = 0
    stack_type  = "IPV4_ONLY"
    subnetwork  = var.network
  }

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
    preemptible         = false
    provisioning_model  = "STANDARD"
  }

  shielded_instance_config {
    enable_integrity_monitoring = true
    enable_secure_boot          = true
    enable_vtpm                 = true
  }

  zone = var.zone

  tags = ["http-server", "https-server", "rke2-nodes"]

  metadata = {
    ssh-keys = "${var.ssh_user}:${var.ssh_public_key}"
  }
}
