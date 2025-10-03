output "name" {
  value = try(harvester_ippool.ip_pool[0].name, null)
}
