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

  # 6443 fronts the kube-apiserver, which 401s every HTTP path (RKE2 disables
  # anonymous auth), so no HTTP health check can pass; TCP is the only probe
  # that works. The other ports serve /ping (rancher via the ingress on
  # 80/443, the rke2 supervisor on 9345).
  health_check {
    protocol = each.key == "6443" ? "TCP" : "HTTP"
    port = "traffic-port"
    path = each.key == "6443" ? null : "/ping"
    interval = 10
    timeout = 6
    healthy_threshold = 3
    unhealthy_threshold = 3
    matcher = each.key == "6443" ? null : "200-399"
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
