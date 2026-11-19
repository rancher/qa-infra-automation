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
  nodes              = [{ count = 2, role = ["etcd", "cp", "worker"] }]
}

run "no_nlb_subnet_skips_lookups_and_keeps_instance_targets" {
  command = apply

  assert {
    condition     = length(data.aws_subnet.nodes) == 0 && length(data.aws_subnet.nlb) == 0
    error_message = "Without aws_nlb_subnet the module must not need ec2:DescribeSubnets."
  }
  assert {
    condition     = aws_lb_target_group.aws_tg_6443[0].target_type == "instance" && aws_lb_target_group.aws_tg_6443[0].ip_address_type == "ipv4"
    error_message = "Existing callers must keep the instance/ipv4 target groups."
  }
  assert {
    condition     = alltrue([for a in aws_lb_target_group_attachment.aws_tg_attachment_6443 : a.target_id == "i-0123456789abcdef0"])
    error_message = "Existing callers must register targets by instance ID."
  }
}

run "dual_stack_nodes_subnet_keeps_instance_targets" {
  command = apply

  variables {
    aws_nlb_subnet = "subnet-nlb"
  }
  override_data {
    target = data.aws_subnet.nodes
    values = { ipv6_native = false, availability_zone = "us-west-1a" }
  }
  override_data {
    target = data.aws_subnet.nlb
    values = { ipv6_native = false, availability_zone = "us-west-1a" }
  }

  assert {
    condition     = aws_lb_target_group.aws_tg_6443[0].target_type == "instance" && aws_lb_target_group.aws_tg_6443[0].ip_address_type == "ipv4"
    error_message = "A dual-stack aws_subnet must keep instance/ipv4 targets."
  }
}

run "ipv6_native_subnet_registers_ipv6_addresses" {
  command = apply

  variables {
    aws_nlb_subnet = "subnet-nlb"
  }
  override_data {
    target = data.aws_subnet.nodes
    values = { ipv6_native = true, availability_zone = "us-west-1a" }
  }
  override_data {
    target = data.aws_subnet.nlb
    values = { ipv6_native = false, availability_zone = "us-west-1a" }
  }

  assert {
    condition = alltrue([for tg in [aws_lb_target_group.aws_tg_80[0], aws_lb_target_group.aws_tg_443[0], aws_lb_target_group.aws_tg_6443[0], aws_lb_target_group.aws_tg_9345[0]] :
    tg.target_type == "ip" && tg.ip_address_type == "ipv6"])
    error_message = "IPv6-native subnets need ip/ipv6 target groups."
  }
  assert {
    condition     = alltrue([for a in aws_lb_target_group_attachment.aws_tg_attachment_9345 : a.target_id == "2600:1f1c:cdf::10"])
    error_message = "IPv6-native subnets must register targets by IPv6 address."
  }
  assert {
    condition     = aws_lb.aws_nlb[0].subnets == toset(["subnet-nlb"])
    error_message = "The NLB must use aws_nlb_subnet."
  }
}

run "ipv6_native_subnet_requires_enable_ipv6" {
  command = plan

  variables {
    aws_nlb_subnet      = "subnet-nlb"
    enable_ipv6         = false
    enable_public_ip    = true
    no_of_bastion_nodes = 0
  }
  override_data {
    target = data.aws_subnet.nodes
    values = { ipv6_native = true, availability_zone = "us-west-1a" }
  }
  override_data {
    target = data.aws_subnet.nlb
    values = { ipv6_native = false, availability_zone = "us-west-1a" }
  }

  expect_failures = [aws_lb.aws_nlb]
}

run "nlb_subnet_must_share_the_nodes_az" {
  command = plan

  variables {
    aws_nlb_subnet = "subnet-nlb"
  }
  override_data {
    target = data.aws_subnet.nodes
    values = { ipv6_native = true, availability_zone = "us-west-1a" }
  }
  override_data {
    target = data.aws_subnet.nlb
    values = { ipv6_native = false, availability_zone = "us-west-1b" }
  }

  expect_failures = [aws_lb.aws_nlb]
}

run "single_cp_skips_the_subnet_lookup" {
  command = plan

  variables {
    nodes = [{ count = 1, role = ["etcd", "cp", "worker"] }]
  }

  assert {
    condition     = length(data.aws_subnet.nodes) == 0 && length(aws_lb.aws_nlb) == 0
    error_message = "Single-cp clusters must not build an NLB or read the subnet."
  }
}
