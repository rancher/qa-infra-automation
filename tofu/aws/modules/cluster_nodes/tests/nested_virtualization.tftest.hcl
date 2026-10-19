mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = { cidr_block = "10.0.0.0/16" }
  }
  mock_data "aws_ec2_instance_type" {
    defaults = { supported_cpu_features = ["nested-virtualization"] }
  }
}

mock_provider "random" {}

# Preserve Optional+Computed CPU settings using the real planner, not mock defaults.
# Used only for a refresh-disabled plan over mock state; AWS endpoints are local.
provider "aws" {
  alias                       = "offline"
  region                      = "us-east-2"
  access_key                  = "offline-test"
  secret_key                  = "offline-test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  skip_region_validation      = true

  endpoints {
    ec2     = "http://127.0.0.1:1"
    iam     = "http://127.0.0.1:1"
    route53 = "http://127.0.0.1:1"
    sts     = "http://127.0.0.1:1"
  }
}

variables {
  public_ssh_key      = "tests/fixtures/nested-worker.pub"
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
    condition     = alltrue([for c in aws_instance.node["master"].cpu_options : c.nested_virtualization != "enabled"])
    error_message = "The combined-role master must not request nested virtualization."
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

run "false_on_unsupported_global_type" {
  command = plan
  variables {
    worker_nested_virtualization = false
    nodes = [
      { count = 1, role = ["etcd", "cp", "worker"] },
      { count = 2, role = ["worker"] },
    ]
  }
  override_data {
    target = data.aws_ec2_instance_type.nested_worker
    values = { supported_cpu_features = [] }
  }

  assert {
    condition = alltrue([
      for name in ["worker-0", "worker-1"] :
      data.aws_ec2_instance_type.nested_worker[name].instance_type == "t3.large"
    ])
    error_message = "Workers without an override must check the global instance type."
  }
  assert {
    condition = alltrue(flatten([
      for node in aws_instance.node : [
        for cpu in node.cpu_options : !contains(["enabled", "disabled"], cpu.nested_virtualization)
      ]
    ]))
    error_message = "False must not send nested CPU options on unsupported workers or the combined-role master."
  }
}

run "false_on_unsupported_override_type" {
  command = plan
  variables {
    worker_nested_virtualization = false
    nodes = [
      { count = 1, role = ["etcd", "cp", "worker"] },
      { count = 2, role = ["worker"], instance_type = "m5.xlarge" },
    ]
  }
  override_data {
    target = data.aws_ec2_instance_type.nested_worker
    values = { supported_cpu_features = [] }
  }

  assert {
    condition = alltrue([
      for name in ["worker-0", "worker-1"] :
      data.aws_ec2_instance_type.nested_worker[name].instance_type == "m5.xlarge"
    ])
    error_message = "Capability checks must use the worker override, not the global instance type."
  }
  assert {
    condition = alltrue(flatten([
      for node in aws_instance.node : [
        for cpu in node.cpu_options : !contains(["enabled", "disabled"], cpu.nested_virtualization)
      ]
    ]))
    error_message = "False must also omit nested CPU options when the unsupported type is a worker override."
  }
}

run "enable_workers_in_mock_state" {
  command = apply
  variables { worker_nested_virtualization = true }
  assert {
    condition     = alltrue([for name in ["worker-0", "worker-1"] : one(aws_instance.node[name].cpu_options).nested_virtualization == "enabled"])
    error_message = "The mocked worker state must start enabled."
  }
}

run "leave_workers_unmanaged" {
  command   = plan
  providers = { aws = aws.offline }
  plan_options {
    refresh = false
  }
  override_data {
    target = data.aws_vpc.selected
    values = { cidr_block = "10.0.0.0/16" }
  }
  override_data {
    target = data.aws_route53_zone.selected
    values = { zone_id = "Z0000000000000" }
  }
  variables { worker_nested_virtualization = null }
  assert {
    condition     = length(data.aws_ec2_instance_type.nested_worker) == 0
    error_message = "Unmanaged mode must not introduce instance-type queries."
  }
  assert {
    condition     = length(local.nested_workers) == 0
    error_message = "An explicit null must omit management of worker CPU options."
  }
  assert {
    condition     = alltrue([for name in ["worker-0", "worker-1"] : one(aws_instance.node[name].cpu_options).nested_virtualization == "enabled"])
    error_message = "Unmanaged mode must preserve nested virtualization on previously enabled workers."
  }
}

run "disable_previously_enabled_workers" {
  command = plan
  variables { worker_nested_virtualization = false }
  assert {
    condition     = alltrue([for name in ["worker-0", "worker-1"] : one(aws_instance.node[name].cpu_options).nested_virtualization == "disabled"])
    error_message = "False must explicitly disable previously enabled workers, not omit their CPU options."
  }
  assert {
    condition     = length(data.aws_ec2_instance_type.nested_worker) == 2
    error_message = "Explicit CPU-option changes must validate the worker types."
  }
  assert {
    condition     = alltrue([for c in aws_instance.node["master"].cpu_options : !contains(["enabled", "disabled"], c.nested_virtualization)])
    error_message = "Disabling must not manage CPU options on the combined-role master."
  }
}
