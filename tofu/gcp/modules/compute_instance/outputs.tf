output "public_dns" {
  value = google_compute_instance.this.network_interface[0].access_config[0].nat_ip
}

output "ssh_key" {
  value = tls_private_key.ssh.private_key_openssh
}