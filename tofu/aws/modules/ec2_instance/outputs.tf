output "public_dns" {
    value = aws_instance.this.public_dns
}

output "private_ip" {
    value = aws_instance.this.private_ip
}

output "id" {
    value = aws_instance.this.id
}
