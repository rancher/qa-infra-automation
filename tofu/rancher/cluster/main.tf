provider "rancher2" {
  api_url   = var.fqdn
  token_key = var.api_key
  insecure  = var.insecure
}

# Only relevant when cloud_provider == "aws"; unused otherwise.
provider "aws" {
  region     = try(var.node_config.aws_region, "us-east-1")
  access_key = try(var.node_config.aws_access_key, null)
  secret_key = try(var.node_config.aws_secret_key, null)
}

locals {
  # Self-provision SG when omitted (aws only).
  create_security_group  = var.cloud_provider == "aws" && length(try(var.node_config.aws_security_group, [])) == 0

  vpc_id               = try(var.node_config.aws_vpc, null)
  subnet_id            = try(var.node_config.aws_subnet, null)
  security_group_names = local.create_security_group ? [aws_security_group.ephemeral[0].name] : try(var.node_config.aws_security_group, [])

  # Egress CIDRs for the ephemeral SG: caller-supplied, or the VPC's own CIDR by default.
  ephemeral_sg_egress_cidrs = coalesce(var.ephemeral_sg_egress_cidrs, local.create_security_group ? [data.aws_vpc.selected[0].cidr_block] : [])

  effective_node_config = merge(var.node_config, {
    aws_security_group = var.cloud_provider == "aws" ? local.security_group_names : try(var.node_config.aws_security_group, [])
  })
}

# Used to compute the ephemeral SG's default egress CIDR (the VPC's own CIDR).
data "aws_vpc" "selected" {
  count = local.create_security_group ? 1 : 0
  id    = local.vpc_id
}

# Ephemeral security group (aws only, created when node_config.aws_security_group omitted).
resource "aws_security_group" "ephemeral" {
  count       = local.create_security_group ? 1 : 0
  name        = "${var.generate_name}-ephemeral-sg"
  description = "Ephemeral security group for ${var.generate_name} (created because node_config.aws_security_group was empty)"
  vpc_id      = local.vpc_id

  # SSH (22) is used by the Rancher server itself to provision this
  # downstream node (not the CI runner). Instead of opening SSH to
  # 0.0.0.0/0, allow it as a source security group so only traffic
  # originating from the Rancher server's own SG is permitted.
  dynamic "ingress" {
    for_each = (var.rancher_server_security_group_id != null && var.rancher_server_security_group_id != "") ? [1] : []
    content {
      description     = "SSH from the Rancher server security group (provisions this node)"
      from_port       = 22
      to_port         = 22
      protocol        = "tcp"
      security_groups = [var.rancher_server_security_group_id]
    }
  }

  ingress {
    description = "SSH from allowed CIDRs"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.ephemeral_sg_ingress_cidrs
  }

  ingress {
    description = "All traffic between instances in this security group"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  # RKE2/Rancher LB health checks and node-to-node traffic on 80/443/6443/9345
  # are addressed via each node's PUBLIC IP, even between nodes in the same
  # VPC/SG - that traffic egresses out through the IGW and re-enters via the
  # destination's public IP, so it arrives tagged with the SOURCE NODE'S
  # PUBLIC IP (not the VPC CIDR, and not var.ephemeral_sg_ingress_cidrs,
  # which is the runner's IP). Since node public IPs aren't known ahead of
  # instance creation (would create a circular dependency with this SG),
  # these ports must accept 0.0.0.0/0 on ingress; egress already has the
  # matching 0.0.0.0/0 exceptions.
  dynamic "ingress" {
    for_each = toset(["80", "443", "6443", "9345"])
    content {
      description = "RKE2/Rancher LB/API via node public IPs ${ingress.value}"
      from_port   = tonumber(ingress.value)
      to_port     = tonumber(ingress.value)
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    description = "Egress to allowed CIDRs"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = local.ephemeral_sg_egress_cidrs
  }

  # Outbound-only exceptions: nodes need internet access for package
  # managers (apt/yum), RKE2/K3s downloads, and container registries.
  # Narrowly scoped to HTTP/HTTPS + DNS so the rest of egress stays
  # restricted to local.ephemeral_sg_egress_cidrs.
  egress {
    description = "Outbound HTTP for package repos/downloads"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound HTTPS for package repos/downloads"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound DNS (TCP)"
    from_port   = 53
    to_port     = 53
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Outbound DNS (UDP)"
    from_port   = 53
    to_port     = 53
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "egress" {
    for_each = toset(["6443", "9345"])
    content {
      description = "Outbound RKE2/Rancher API to masters public IP ${egress.value}"
      from_port   = tonumber(egress.value)
      to_port     = tonumber(egress.value)
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  tags = {
    Name = "${var.generate_name}-ephemeral-sg"
  }
}

resource "random_string" "suffix" {
  length  = 3
  upper   = false
  special = false
}

module "rancher2_cloud_credential" {
  source = "../cloudcredential"
  api_key = var.api_key

  name = "${var.cloud_provider}-${random_string.suffix.result}"
  cloud_provider = var.cloud_provider
  node_config = local.effective_node_config
  fqdn = var.fqdn

  create_new = var.create_new
  insecure = var.insecure
}


module "rancher2_machine_config_v2" {
  source = "../machineconfig"
  cloud_provider = var.cloud_provider
  node_config = local.effective_node_config

  count                    = var.create_new ? 1 : 0
  generate_name            = var.generate_name

  fleet_namespace         = try(var.fleet_namespace, null)
  annotations             = try(var.annotations, null)
  labels                  = try(var.labels, null)
}

resource "rancher2_cluster_v2" "rancher2_cluster_v2" {
  name                                                       = "${var.generate_name}-${random_string.suffix.result}"
  kubernetes_version                                         = var.kubernetes_version
  enable_network_policy                                      = var.is_network_policy
  default_pod_security_admission_configuration_template_name = var.psa
  default_cluster_role_for_project_members                   = "user"
  
  rke_config {
    machine_global_config = var.machine_global_config != null ? yamlencode(var.machine_global_config) : null

    dynamic "machine_pools" {
      for_each = var.machine_pools
      iterator = machine_pool
      content {
        name                         = var.generate_name
        cloud_credential_secret_name = module.rancher2_cloud_credential.cloud_credential_id
        control_plane_role           = machine_pool.value.control_plane_role
        etcd_role                    = machine_pool.value.etcd_role
        worker_role                  = machine_pool.value.worker_role
        quantity                     = machine_pool.value.quantity

        machine_config {
          kind = module.rancher2_machine_config_v2[0].machine_kind
          name = module.rancher2_machine_config_v2[0].machine_name
        }
        dynamic "taints" {
          for_each = try(var.node_taints, [])
          iterator = taint
          content {
            key        = try(taint.value.key, null)
            value      = try(taint.value.value, null)
            effect     = try(taint.value.effect, null)
          }
        }
      }
    }
    upgrade_strategy {
      control_plane_concurrency = "10%"
      worker_concurrency        = "10%"
    }
    etcd {
      disable_snapshots      = false
      snapshot_schedule_cron = ""
      snapshot_retention     = 5
    }
  }
}

data "rancher2_cluster_v2" "rancher2_cluster_v2" {
  name = rancher2_cluster_v2.rancher2_cluster_v2.name
}

