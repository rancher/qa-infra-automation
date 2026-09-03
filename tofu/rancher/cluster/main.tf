provider "rancher2" {
  api_url   = var.fqdn
  token_key = var.api_key
  insecure  = var.insecure
}

# Only used to discover the downstream node(s)' public IP(s) (once
# provisioned) and manage their SG rules natively (see
# downstream_agent_checkin_ingress/egress below). Reuses the same AWS
# credentials/region already supplied in node_config.
provider "aws" {
  access_key = try(var.node_config.aws_access_key, null)
  secret_key = try(var.node_config.aws_secret_key, null)
  region     = try(var.node_config.aws_region, null)
}

resource "random_string" "suffix" {
  length  = 3
  upper   = false
  special = false
}

# Injected into the downstream node(s)' AWS tags so they can be uniquely
# discovered afterwards via data.aws_instances - the shared ephemeral SG
# (node_config.aws_security_group) also contains the original RKE2 nodes
# from cluster_nodes, so filtering by SG alone isn't enough to isolate these
# downstream nodes. amazonec2_config.tags is a docker-machine style
# "key1,value1,key2,value2" string (not a map), so the discovery tag is
# appended to whatever the caller already supplied.
locals {
  downstream_discovery_tag_key   = "qa-infra-downstream-node"
  downstream_discovery_tag_value = "${var.generate_name}-${random_string.suffix.result}"
  node_config_with_discovery_tag = var.cloud_provider == "aws" ? merge(var.node_config, {
    aws_tags = join(",", compact([
      try(var.node_config.aws_tags, null),
      "${local.downstream_discovery_tag_key},${local.downstream_discovery_tag_value}",
    ]))
  }) : merge(var.node_config, { aws_tags = try(var.node_config.aws_tags, null) })
}

module "rancher2_cloud_credential" {
  source = "../cloudcredential"
  api_key = var.api_key

  name = "${var.cloud_provider}-${random_string.suffix.result}"
  cloud_provider = var.cloud_provider
  node_config = var.node_config
  fqdn = var.fqdn

  create_new = var.create_new
  insecure = var.insecure
}


module "rancher2_machine_config_v2" {
  source = "../machineconfig"
  cloud_provider = var.cloud_provider
  node_config = local.node_config_with_discovery_tag

  count                    = var.create_new ? 1 : 0
  generate_name            = var.generate_name

  fleet_namespace         = try(var.fleet_namespace, null)
  annotations             = try(var.annotations, null)
  labels                  = try(var.labels, null)
}

resource "time_sleep" "wait_60_seconds" {
  create_duration = "60s"
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

data "aws_security_groups" "downstream_sg" {
  count = var.cloud_provider == "aws" ? 1 : 0
  filter {
    name   = "group-name"
    values = try(var.node_config.aws_security_group, [])
  }
  filter {
    name   = "vpc-id"
    values = [try(var.node_config.aws_vpc, "")]
  }
}

# The downstream node(s)' public IPs can't be read from any native Tofu
# resource (they're created by the rancher2/node-driver machinery outside
# this module's resource graph). Instead, discover them via their unique
# tag (see node_config_with_discovery_tag above) using data.aws_instances.
#
# Caveat: unlike a script that can poll/retry, a data source is read once
# per apply. If the AWS instance(s) somehow still aren't visible by the
# time this is read, public_ips will be empty and no SG rule is created
# this apply - re-running `tofu apply` resolves it (idempotent).
data "aws_instances" "downstream_node" {
  count      = var.cloud_provider == "aws" ? 1 : 0
  depends_on = [time_sleep.wait_60_seconds]

  filter {
    name   = "tag:${local.downstream_discovery_tag_key}"
    values = [local.downstream_discovery_tag_value]
  }
  instance_state_names = ["pending", "running"]
}

locals {
  downstream_node_public_ips = var.cloud_provider == "aws" ? try(data.aws_instances.downstream_node[0].public_ips, []) : []
  downstream_sg_id           = var.cloud_provider == "aws" ? try(data.aws_security_groups.downstream_sg[0].ids[0], "") : ""

  # for_each's key set must be known at plan time. data.aws_instances.downstream_node
  # is deliberately deferred to apply (depends_on the machine_config module), so any
  # collection derived from its result (downstream_node_public_ips) is unknown at
  # plan and can't drive for_each's key set directly. Instead, bound the key set by
  # the total node quantity requested in var.machine_pools (a plain variable, known
  # at plan) - one "slot" per expected node - and only use the (possibly
  # unknown-until-apply) IP list as a value via try()/index, which is allowed.
  downstream_node_slots = range(sum([for mp in var.machine_pools : mp.quantity]))
  downstream_agent_checkin_rules = {
    for pair in setproduct(["80", "443"], local.downstream_node_slots) :
    "${pair[0]}-${pair[1]}" => {
      port  = pair[0]
      index = pair[1]
    }
  }
}

# NOTE: cidr_ipv4 falls back to a non-matching placeholder ("255.255.255.255/32")
# for any slot whose IP hasn't been discovered yet (e.g. first apply before the
# node driver finishes creating the instance), so the resource still applies
# cleanly without granting an unintended wide-open rule. Re-running `tofu apply`
# once every configured node is discoverable converges all slots to their real
# per-node /32 CIDR.
resource "aws_vpc_security_group_ingress_rule" "downstream_agent_checkin_ingress" {
  for_each = var.cloud_provider == "aws" ? local.downstream_agent_checkin_rules : {}

  security_group_id = local.downstream_sg_id
  description        = "Downstream node ${local.downstream_discovery_tag_value} agent checkin ${each.value.port} (slot ${each.value.index})"
  ip_protocol        = "tcp"
  from_port          = tonumber(each.value.port)
  to_port            = tonumber(each.value.port)
  cidr_ipv4          = "${try(local.downstream_node_public_ips[each.value.index], "255.255.255.255")}/32"

  lifecycle {
    precondition {
      condition     = local.downstream_sg_id != ""
      error_message = "Could not resolve the shared downstream SG id. Check node_config.aws_security_group/aws_vpc."
    }
  }
}

resource "aws_vpc_security_group_egress_rule" "downstream_agent_checkin_egress" {
  for_each = var.cloud_provider == "aws" ? local.downstream_agent_checkin_rules : {}

  security_group_id = local.downstream_sg_id
  description        = "Downstream node ${local.downstream_discovery_tag_value} agent checkin ${each.value.port} (slot ${each.value.index})"
  ip_protocol        = "tcp"
  from_port          = tonumber(each.value.port)
  to_port            = tonumber(each.value.port)
  cidr_ipv4          = "${try(local.downstream_node_public_ips[each.value.index], "255.255.255.255")}/32"

  lifecycle {
    precondition {
      condition     = local.downstream_sg_id != ""
      error_message = "Could not resolve the shared downstream SG id. Check node_config.aws_security_group/aws_vpc."
    }
  }
}

