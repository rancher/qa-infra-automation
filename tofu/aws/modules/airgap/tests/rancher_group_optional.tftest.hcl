# The AWS provider validates ARN shape at plan time, so random mock strings fail.
mock_provider "aws" {
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-2:123456789012:loadbalancer/net/unit/0123456789abcdef" }
  }
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-2:123456789012:targetgroup/unit/0123456789abcdef" }
  }
}

mock_provider "random" {}

variables {
  user_id             = "unit"
  ssh_key             = "unused-in-plan"
  ssh_key_name        = "unit"
  aws_region          = "us-east-2"
  aws_ami             = "ami-0123456789abcdef0"
  aws_hostname_prefix = "unit-airgap"
  aws_route53_zone    = "example.invalid"
  aws_ssh_user        = "example"
  aws_security_group  = ["sg-0123456789abcdef0"]
  aws_vpc             = "vpc-0123456789abcdef0"
  aws_volume_size     = 40
  aws_subnet_airgap   = "subnet-0123456789abcdef0"
  aws_subnet_bastion  = "subnet-0123456789abcdef1"
  instance_type       = "t3.large"
  provision_registry  = false
}

run "lbs_created_with_rancher_group" {
  command = plan
  variables {
    node_groups = { rancher = 1, server = 1 }
  }
  assert {
    condition     = length(module.load_balancer) == 1 && length(module.route53) == 1
    error_message = "A rancher group must still get its load balancers and DNS records."
  }
}

run "plans_without_rancher_group" {
  command = plan
  variables {
    node_groups = { server = 1, worker = 1 }
  }
  assert {
    condition     = length(module.load_balancer) == 0 && length(module.route53) == 0
    error_message = "No rancher group means no load balancers or DNS records."
  }
  assert {
    condition     = length(local.target_groups) == 0
    error_message = "No target groups should be attached without load balancers."
  }
}
