output "dns_name" {
    value = aws_lb.this.dns_name
}

output "target_groups" {
  value = [for port in var.ports : aws_lb_target_group.tg[port]]
}
