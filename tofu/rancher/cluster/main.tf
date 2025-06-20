provider "rancher2" {
  api_url   = var.fqdn
  token_key = var.api_key
  insecure  = var.insecure
}

resource "random_string" "suffix" {
  length  = 3
  upper   = false
  special = false
}


resource "rancher2_cloud_credential" "rancher2_cloud_credential" {
  count = var.create_new ? 1 : 0
  name  = "newcred"
  
  dynamic "amazonec2_credential_config" {
    for_each = var.cloud_provider == "aws" ? [1] : []
    content {
      access_key     = var.node_config.access_key
      secret_key     = var.node_config.secret_key
      default_region = var.node_config.aws_region
    }
  }
  dynamic "linode_credential_config" {
    for_each = var.cloud_provider == "linode" ? [1] : []
    content {
      token = var.node_config.token
    }
  }
  dynamic "harvester_credential_config" {
    for_each = var.cloud_provider == "harvester" ? [1] : []
    content {
      cluster_id         = var.node_config.cluster_v1_id
      cluster_type       = var.node_config.cluster_type
      kubeconfig_content = var.node_config.kubeconfig_content
    }
  }
}

resource "rancher2_machine_config_v2" "rancher2_machine_config_v2" {
  count                    = var.create_new ? 1 : 0
  generate_name            = var.generate_name

  fleet_namespace         = try(var.fleet_namespace, null)
  annotations             = try(var.annotations, null)
  labels                  = try(var.labels, null)

  dynamic "amazonec2_config" {
    for_each = var.cloud_provider == "aws" ? [1] : []
    content {
      ami                        = try(var.node_config.aws_ami, null)
      region                     = try(var.node_config.aws_region, null)
      security_group             = try(var.node_config.aws_security_group_names, null)
      subnet_id                  = try(var.node_config.aws_subnet, null)
      vpc_id                     = try(var.node_config.aws_vpc, null)
      zone                       = try(var.node_config.aws_availability_zone, null)
      access_key                 = try(var.node_config.access_key, null)
      block_duration_minutes     = try(var.node_config.aws_block_duration_minutes, null)
      device_name                = try(var.node_config.aws_device_name, null)
      encrypt_ebs_volume         = try(var.node_config.aws_encrypt_ebs_volume, null)
      endpoint                   = try(var.node_config.aws_endpoint, null)
      http_endpoint              = try(var.node_config.aws_http_endpoint, null)
      http_tokens                = try(var.node_config.aws_http_tokens, null)
      iam_instance_profile       = try(var.node_config.aws_iam_instance_profile, null)
      insecure_transport         = try(var.node_config.aws_insecure_transport, null)
      instance_type              = try(var.node_config.aws_instance_type, null)
      kms_key                    = try(var.node_config.aws_kms_key, null)
      monitoring                 = try(var.node_config.aws_monitoring, null)
      open_port                  = try(var.node_config.aws_open_port, null)
      private_address_only       = try(var.node_config.aws_private_address_only, null)
      request_spot_instance      = try(var.node_config.aws_request_spot_instance, null)
      retries                    = try(var.node_config.aws_retries, null)
      root_size                  = try(var.node_config.aws_volume_size, null)
      secret_key                 = try(var.node_config.secret_key, null)
      security_group_readonly    = try(var.node_config.aws_security_group_readonly, null)
      session_token              = try(var.node_config.aws_session_token, null)
      spot_price                 = try(var.node_config.aws_spot_price, null)
      ssh_user                   = try(var.node_config.aws_ssh_user, null)
      tags                       = try(var.node_config.aws_tags, null)
      use_ebs_optimized_instance = try(var.node_config.aws_use_ebs_optimized_instance, null)
      use_private_address        = try(var.node_config.aws_private_ip_address, null)
      userdata                   = try(var.node_config.aws_userdata, null)
      volume_type                = try(var.node_config.aws_volume_type, null)
    }
  }

  dynamic "linode_config" {
    for_each = var.cloud_provider == "linode" ? [1] : []
    content {
      authorized_users  = try(var.node_config.linode_authorized_users, null)
      create_private_ip = try(var.node_config.linode_create_private_ip, null)
      docker_port       = try(var.node_config.linode_docker_port, null)
      image             = try(var.node_config.linode_image, null)
      instance_type     = try(var.node_config.linode_instance_type, null)
      label             = try(var.node_config.linode_label, null)
      region            = try(var.node_config.linode_region, null)
      root_pass         = try(var.node_config.linode_root_pass, null)
      ssh_port          = try(var.node_config.linode_ssh_port, null)
      ssh_user          = try(var.node_config.linode_ssh_user, null)
      stackscript       = try(var.node_config.linode_stackscript, null)
      stackscript_data  = try(var.node_config.linode_stackscript_data, null)
      swap_size         = try(var.node_config.linode_swap_size, null)
      tags              = try(var.node_config.linode_tags, null)
      token             = try(var.node_config.linode_token, null)
      ua_prefix         = try(var.node_config.linode_ua_prefix, null)
    }
  }

  dynamic "harvester_config" {
    for_each = var.cloud_provider == "harvester" ? [1] : []
    content {
      vm_namespace = try(var.node_config.harvester_vm_namespace, null)
      cpu_count = try(var.node_config.harvester_cpu_count, null)
      memory_size = try(var.node_config.harvester_memory_size, null)
      disk_info = try(var.node_config.harvester_disk_info, null)
      ssh_user = try(var.node_config.harvester_ssh_user, null)
      ssh_password = try(var.node_config.harvester_ssh_password, null)
      network_info = try(var.node_config.harvester_network_info, null)
      user_data = try(var.node_config.harvester_user_data, null)
      network_data = try(var.node_config.harvester_network_data, null)
      vm_affinity = try(var.node_config.harvester_vm_affinity, null)
    }
  }
}

resource "rancher2_cluster_v2" "rancher2_cluster_v2" {
  name                                                       = "${var.generate_name}-${random_string.suffix.result}"
  kubernetes_version                                         = var.kubernetes_version
  enable_network_policy                                      = var.is_network_policy
  default_pod_security_admission_configuration_template_name = var.psa
  default_cluster_role_for_project_members                   = "user"
  
  rke_config {
    dynamic "machine_pools" {
      for_each = var.machine_pools
      iterator = machine_pool
      content {
        name                         = var.generate_name
        cloud_credential_secret_name = rancher2_cloud_credential.rancher2_cloud_credential[0].id
        control_plane_role           = machine_pool.value.control_plane_role
        etcd_role                    = machine_pool.value.etcd_role
        worker_role                  = machine_pool.value.worker_role
        quantity                     = machine_pool.value.quantity

        machine_config {
          kind = rancher2_machine_config_v2.rancher2_machine_config_v2[0].kind
          name = rancher2_machine_config_v2.rancher2_machine_config_v2[0].name
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

