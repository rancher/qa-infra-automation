# Every variable validation in variables.tf, so CI catches a regression in any of them.
mock_provider "aws" {
  mock_data "aws_route53_zone" {
    defaults = { zone_id = "Z0000000000000000000" }
  }
  mock_resource "aws_instance" {
    defaults = { id = "i-0123456789abcdef0", ipv6_addresses = ["2600:1f1c:cdf::10"] }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-west-1:123456789012:loadbalancer/net/unit-nlb/0123456789abcdef" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-west-1:123456789012:targetgroup/unit-tg/0123456789abcdef" }
  }
}

mock_provider "random" {}

variables {
  public_ssh_key      = "tests/fixtures/test.pub"
  aws_region          = "us-west-1"
  aws_ami             = "ami-0123456789abcdef0"
  aws_hostname_prefix = "unit-nlb"
  aws_route53_zone    = "example.invalid"
  aws_ssh_user        = "ubuntu"
  aws_security_group  = ["sg-0123456789abcdef0"]
  aws_vpc             = "vpc-0123456789abcdef0"
  aws_subnet          = "subnet-nodes"
  aws_volume_size     = 40
  aws_volume_type     = "gp3"
  instance_type       = "t3.large"
  enable_ipv6         = true
  enable_public_ip    = false
  no_of_bastion_nodes = 1
  aws_bastion_subnet  = "subnet-bastion"
  # Pinned so a local terraform.tfvars, which tofu test also loads, cannot leak in.
  kube_api_host_ipv6 = false
  aws_nlb_subnet     = null
  nodes              = [{ count = 1, role = ["etcd", "cp", "worker"] }]
}

run "valid_ipv6_only_baseline_plans" {
  command = plan
}

run "bastion_required_without_public_ipv4" {
  command = plan

  variables {
    no_of_bastion_nodes = 0
  }

  expect_failures = [var.no_of_bastion_nodes]
}

run "at_most_one_bastion" {
  command = plan

  variables {
    no_of_bastion_nodes = 2
  }

  expect_failures = [var.no_of_bastion_nodes]
}

run "bastion_subnet_required_with_a_bastion" {
  command = plan

  variables {
    aws_bastion_subnet = ""
  }

  expect_failures = [var.aws_bastion_subnet]
}

run "a_reachable_address_family_is_required" {
  command = plan

  variables {
    enable_ipv6 = false
  }

  expect_failures = [var.enable_public_ip]
}

run "kube_api_host_ipv6_requires_ipv6" {
  command = plan

  variables {
    enable_public_ip   = true
    enable_ipv6        = false
    kube_api_host_ipv6 = true
  }

  expect_failures = [var.kube_api_host_ipv6]
}

run "a_cp_node_is_required" {
  command = plan

  variables {
    nodes = [{ count = 1, role = ["worker"] }]
  }

  expect_failures = [var.nodes]
}

run "role_sets_must_be_distinct" {
  command = plan

  variables {
    nodes = [{ count = 1, role = ["etcd", "cp"] }, { count = 1, role = ["etcd", "cp"] }]
  }

  expect_failures = [var.nodes]
}
