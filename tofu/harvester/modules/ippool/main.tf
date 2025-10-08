resource "random_string" "random_suffix" {
  length  = 3
  special = false
  upper   = false
}


resource "harvester_ippool" "ip_pool" {
    count = var.create_new ? 1 : 0
    name      = "${var.generate_name}-${random_string.random_suffix.result}"

    range {
        start   = var.range_ip_start
        end     = var.range_ip_end
        gateway    = var.gateway_ip
        subnet = var.subnet_cidr
        }

    selector {
        network = "${var.namespace}/${var.backend_network_name}"

        scope {
        namespace = "*"
        project   = "*"
        guest_cluster = "*"
        }

        priority = 100
    }
}