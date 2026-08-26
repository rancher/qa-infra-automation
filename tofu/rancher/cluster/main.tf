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
  # Self-provision VPC/subnet/SG when omitted (aws only). Mirrors cluster_nodes/airgap.
  create_vpc             = var.cloud_provider == "aws" && try(var.node_config.aws_vpc, null) == null
  create_subnet          = var.cloud_provider == "aws" && try(var.node_config.aws_subnet, null) == null
  create_security_group  = var.cloud_provider == "aws" && length(try(var.node_config.aws_security_group, [])) == 0

  vpc_id             = local.create_vpc ? aws_vpc.ephemeral[0].id : try(var.node_config.aws_vpc, null)
  subnet_id          = local.create_subnet ? aws_subnet.ephemeral[0].id : try(var.node_config.aws_subnet, null)
  security_group_ids = local.create_security_group ? [aws_security_group.ephemeral[0].id] : try(var.node_config.aws_security_group, [])

  # Overlay resolved vpc/subnet/sg back into node_config. Always merge (rather
  # than branching between merge(...) and var.node_config) to avoid
  # "Inconsistent conditional result types" errors, since node_config is typed
  # `any` and the two ternary branches would otherwise have differing object
  # types. For non-aws providers these keys are no-ops (unused downstream).
  effective_node_config = merge(var.node_config, {
    aws_vpc            = var.cloud_provider == "aws" ? local.vpc_id : try(var.node_config.aws_vpc, null)
    aws_subnet         = var.cloud_provider == "aws" ? local.subnet_id : try(var.node_config.aws_subnet, null)
    aws_security_group = var.cloud_provider == "aws" ? local.security_group_ids : try(var.node_config.aws_security_group, [])
  })
}

# Ephemeral network (aws only, created when vpc/subnet omitted).

resource "aws_vpc" "ephemeral" {
  count                = local.create_vpc ? 1 : 0
  cidr_block           = var.ephemeral_vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${var.generate_name}-ephemeral-vpc"
  }
}

data "aws_availability_zones" "available" {
  count = local.create_subnet ? 1 : 0
  state = "available"
}

resource "aws_subnet" "ephemeral" {
  count                   = local.create_subnet ? 1 : 0
  vpc_id                  = local.vpc_id
  cidr_block              = var.ephemeral_subnet_cidr
  availability_zone       = data.aws_availability_zones.available[0].names[0]
  map_public_ip_on_launch = true

  tags = {
    Name = "${var.generate_name}-ephemeral-subnet"
  }
}

resource "aws_internet_gateway" "ephemeral" {
  count  = local.create_vpc ? 1 : 0
  vpc_id = aws_vpc.ephemeral[0].id

  tags = {
    Name = "${var.generate_name}-ephemeral-igw"
  }
}

resource "aws_route_table" "ephemeral" {
  count  = local.create_vpc ? 1 : 0
  vpc_id = aws_vpc.ephemeral[0].id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.ephemeral[0].id
  }

  tags = {
    Name = "${var.generate_name}-ephemeral-rt"
  }
}

resource "aws_route_table_association" "ephemeral" {
  # Only needed when we created our own route table (create_vpc); a subnet
  # added to an existing VPC uses its main route table automatically.
  count          = local.create_vpc && local.create_subnet ? 1 : 0
  subnet_id      = aws_subnet.ephemeral[0].id
  route_table_id = aws_route_table.ephemeral[0].id
}

# Mirrors tofu/aws/modules/airgap's self-provisioned SG: SSH, full intra-group
# traffic, and the RKE2/Rancher NLB listener ports, plus unrestricted egress.
resource "aws_security_group" "ephemeral" {
  count       = local.create_security_group ? 1 : 0
  name        = "${var.generate_name}-ephemeral-sg"
  description = "Ephemeral security group for ${var.generate_name} (created because node_config.aws_security_group was empty)"
  vpc_id      = local.vpc_id

  ingress {
    description = "SSH from anywhere"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "All traffic between instances in this security group"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
  }

  dynamic "ingress" {
    for_each = toset(["80", "443", "6443", "9345"])
    content {
      description = "LB listener ${ingress.value}"
      from_port   = tonumber(ingress.value)
      to_port     = tonumber(ingress.value)
      protocol    = "tcp"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  egress {
    description = "All outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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

