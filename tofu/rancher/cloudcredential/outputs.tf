output "cloud_credential_id" {
  value = data.rancher2_cloud_credential.this.id
}

output "cloud_credential_name" {
  value = data.rancher2_cloud_credential.this.name
}

output "cloud_credential_object" {
  value = data.rancher2_cloud_credential.this
}