output "rancher_server_url" {
  description = "URL for the Rancher UI."
  value       = "https://${aws_route53_record.rancher_record.fqdn}"
}

output "bastion_public_ip" {
  description = "Public IP address of the bastion host."
  value       = aws_instance.bastion.public_ip
}

output "bastion_ssh_command" {
  description = "Command to SSH into the bastion host."
  value       = "ssh -i ${var.private_key_path} ubuntu@${aws_instance.bastion.public_ip}"
}

output "internal_private_key_path" {
  description = "Path to the generated private key used for internal communication."
  value       = local_file.bastion_to_target_private_key.filename
}

output "coredns_patch_instruction" {
  description = "Command to patch CoreDNS for IPv6 DNS resolution."
  value = <<EOT
After the cluster is running, you may need to patch CoreDNS to ensure public DNS resolution over IPv6.
Run the following from a machine with kubectl configured:

kubectl -n kube-system get cm coredns -o json \
| jq '.data.Corefile |= sub("forward . /etc/resolv.conf", "forward . 2001:4860:4860::8888 2001:4860:4860::8844")' \
| kubectl apply -f -

Then, restart the CoreDNS pods:
kubectl -n kube-system rollout restart deployment coredns
EOT
}
