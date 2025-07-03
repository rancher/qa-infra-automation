output "machine_kind" {
  value = rancher2_machine_config_v2.rancher2_machine_config_v2[0].kind
}

output "machine_name" {
  value = rancher2_machine_config_v2.rancher2_machine_config_v2[0].name
}

output "machine_object" {
  value = rancher2_machine_config_v2.rancher2_machine_config_v2
}