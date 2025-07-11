data "aws_route53_zone" "this" {
  name = var.zone_name
  private_zone = false
}

resource "aws_route53_record" "record" {
  zone_id = data.aws_route53_zone.this.zone_id
  name = var.record_name
  type = "CNAME"
  ttl = 300
  records = [var.dns_name]
}
