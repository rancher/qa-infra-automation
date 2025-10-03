output "name" {
  value = try(harvester_loadbalancer.new_lb[0].name, null)
}
