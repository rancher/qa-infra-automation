output "registry_public_dns" {
  value = aws_instance.registry.public_dns
}

output "rke2_bastion_public_dns" {
    value = aws_instance.rke2_bastion.public_dns
}

output "rke2_server1_private_ip" {
  value = aws_instance.rke2_server1.private_ip
}

output "rke2_server2_private_ip" {
  value = aws_instance.rke2_server2.private_ip
}

output "rke2_server3_private_ip" {
  value = aws_instance.rke2_server3.private_ip
}