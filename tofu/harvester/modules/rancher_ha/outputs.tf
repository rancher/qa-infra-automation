output "ip" {
  value = [for vm in harvester_virtualmachine.vm : vm.network_interface[0].ip_address] 

}