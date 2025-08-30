# VM Basic Information
output "vm_id" {
  description = "The ID of the virtual machine"
  value       = vsphere_virtual_machine.vm.id
}

output "vm_uuid" {
  description = "The UUID of the virtual machine"
  value       = vsphere_virtual_machine.vm.uuid
}

output "vm_name" {
  description = "The name of the virtual machine"
  value       = vsphere_virtual_machine.vm.name
}

# Network Information
output "ip_address" {
  description = "The primary IP address of the virtual machine"
  value       = vsphere_virtual_machine.vm.default_ip_address
}

output "guest_ip_addresses" {
  description = "All IP addresses assigned to the virtual machine"
  value       = vsphere_virtual_machine.vm.guest_ip_addresses
}

# VM Configuration
output "num_cpus" {
  description = "Number of CPUs assigned to the virtual machine"
  value       = vsphere_virtual_machine.vm.num_cpus
}

output "memory" {
  description = "Memory in MB assigned to the virtual machine"
  value       = vsphere_virtual_machine.vm.memory
}

# Complete VM object for advanced use cases
output "vm" {
  description = "Complete virtual machine resource object"
  value       = vsphere_virtual_machine.vm
}
