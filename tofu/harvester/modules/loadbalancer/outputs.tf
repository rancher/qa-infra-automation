output "name" {
  value = try(harvester_loadbalancer.new_lb[0].name, null)
}
output "ip_address" {
  value = try(harvester_loadbalancer.new_lb[0].ip_address, null)
}