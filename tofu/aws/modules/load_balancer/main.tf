resource "aws_lb" "this" {
  name = var.name
  internal = var.internal
  load_balancer_type = "network"
  subnets = [var.subnet_id]
  tags = {
    Name = var.name
  }
}

resource "aws_lb_target_group" "tg" {
  for_each = toset(var.ports)
  name = "${var.name}-tg-${each.key}"
  port = each.key
  protocol = "TCP"
  vpc_id = var.vpc_id

  health_check {
    protocol = "HTTP"
    port = "traffic-port"
    path = "/ping"
    interval = 10
    timeout = 6
    healthy_threshold = 3
    unhealthy_threshold = 3
    matcher = "200-399"
  }
}

resource "aws_lb_listener" "listener" {
  for_each = aws_lb_target_group.tg
  load_balancer_arn = aws_lb.this.arn
  port = each.value.port
  protocol = "TCP"
  default_action {
    type = "forward"
    target_group_arn = each.value.arn
  }
}
