
resource "random_string" "random_suffix" {
  length  = 3
  special = false
  upper   = false
}

module "harvester_ippool" {
  source = "../ippool"

  create_new = var.ippool_name == null || var.ippool_name == "" ? true : false

  gateway_ip = var.gateway_ip
  backend_network_name = var.backend_network_name
  subnet_cidr = var.subnet_cidr
  range_ip_start = var.range_ip_start
  range_ip_end = var.range_ip_end
  generate_name = var.generate_name
  namespace = var.namespace
}


resource "harvester_loadbalancer" "new_lb" {
  count = var.create_new ? 1 : 0
  
  name = "lb-${var.generate_name}-${random_string.random_suffix.result}"
  namespace = var.namespace
  dynamic "listener" {
    for_each = var.ports
    content {
      backend_port = listener.value
      port         = listener.value
      protocol     = "tcp"
      name = "lstn-${var.generate_name}-${listener.value}"
    }
  }

  backend_selector {
    key = var.lookup_label_key
    values = var.lookup_label_values
  }

  workload_type = var.workload_type

  healthcheck {
    port = var.ports[0]
    failure_threshold = var.healthcheck_failure_threshold
    success_threshold = var.healthcheck_success_threshold
    period_seconds = var.healthcheck_heartbeat
    timeout_seconds = var.healthcheck_timeout
  }


  ipam = var.ipam
  ippool = var.ipam == "pool" ? (var.ippool_name != null && var.ippool_name != "" ? var.ippool_name : module.harvester_ippool.name) : null 
}
