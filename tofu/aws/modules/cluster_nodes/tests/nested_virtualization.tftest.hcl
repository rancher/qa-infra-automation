mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = { cidr_block = "10.0.0.0/16" }
  }
  mock_data "aws_ec2_instance_type" {
    defaults = { supported_cpu_features = ["nested-virtualization"] }
  }
}

mock_provider "random" {}

variables {
  public_ssh_key      = "tests/nested_virtualization.tftest.hcl"
  aws_region          = "us-east-2"
  aws_ami             = "ami-0123456789abcdef0"
  aws_hostname_prefix = "unit-kata"
  aws_route53_zone    = "example.invalid"
  aws_ssh_user        = "example"
  aws_security_group  = ["sg-0123456789abcdef0"]
  aws_vpc             = "vpc-0123456789abcdef0"
  aws_subnet          = "subnet-0123456789abcdef0"
  aws_volume_size     = 40
  aws_volume_type     = "gp3"
  instance_type       = "t3.large"
  airgap_setup        = false
  proxy_setup         = false
  nodes = [
    { count = 1, role = ["etcd", "cp", "worker"] },
    { count = 2, role = ["worker"], instance_type = "c7i.2xlarge" },
  ]
}

run "unchanged_by_default" {
  command = plan
  assert {
    condition     = length(data.aws_ec2_instance_type.nested_worker) == 0
    error_message = "Existing callers must not require extra EC2 permissions."
  }
  assert {
    condition     = length(local.nested_workers) == 0
    error_message = "Existing callers must not enable nested virtualization."
  }
}

run "only_workers_opt_in" {
  command = plan
  variables { worker_nested_virtualization = true }
  assert {
    condition     = toset(keys(local.nested_workers)) == toset(["worker-0", "worker-1"])
    error_message = "Do not change combined-role control-plane nodes."
  }
  assert {
    condition = alltrue([
      for name in ["worker-0", "worker-1"] :
      one(aws_instance.node[name].cpu_options).nested_virtualization == "enabled"
      && data.aws_ec2_instance_type.nested_worker[name].instance_type == "c7i.2xlarge"
    ])
    error_message = "Both workers must use their override and request nested virtualization."
  }
}

run "unsupported_type_rejected" {
  command = plan
  variables { worker_nested_virtualization = true }
  override_data {
    target = data.aws_ec2_instance_type.nested_worker
    values = { supported_cpu_features = [] }
  }
  expect_failures = [data.aws_ec2_instance_type.nested_worker]
}
