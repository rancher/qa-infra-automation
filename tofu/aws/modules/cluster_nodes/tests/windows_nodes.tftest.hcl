mock_provider "aws" {
  mock_data "aws_vpc" {
    defaults = { cidr_block = "10.0.0.0/16" }
  }
  mock_resource "aws_instance" {
    defaults = { public_ip = "198.51.100.7" }
  }
  # apply-mode runs validate these ARNs, so the mock default must be well formed.
  mock_resource "aws_lb_target_group" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-2:123456789012:targetgroup/mock/0123456789abcdef" }
  }
  mock_resource "aws_lb" {
    defaults = { arn = "arn:aws:elasticloadbalancing:us-east-2:123456789012:loadbalancer/net/mock/0123456789abcdef" }
  }
}

mock_provider "random" {}

variables {
  public_ssh_key             = "tests/fixtures/windows-rsa.pub"
  aws_region                 = "us-east-2"
  aws_ami                    = "ami-0123456789abcdef0"
  aws_ami_windows            = "ami-0fedcba9876543210"
  aws_hostname_prefix        = "unit-win"
  aws_route53_zone           = "example.invalid"
  aws_ssh_user               = "example"
  aws_security_group         = []
  aws_vpc                    = "vpc-0123456789abcdef0"
  aws_subnet                 = "subnet-0123456789abcdef0"
  aws_volume_size            = 40
  aws_volume_type            = "gp3"
  instance_type              = "t3.large"
  instance_type_windows      = "t3.xlarge"
  airgap_setup               = false
  proxy_setup                = false
  windows_enable_rdp         = true
  ssh_allowed_cidrs          = ["203.0.113.10/32"]
  ephemeral_sg_ingress_cidrs = ["203.0.113.10/32"]
  nodes = [
    { count = 1, role = ["etcd", "cp", "worker"] },
    { count = 1, role = ["worker"], os = "windows" },
    { count = 1, role = ["worker"], os = "windows", instance_type = "m5.2xlarge" },
  ]
}

run "windows_instance_type_honors_group_override" {
  command = plan
  assert {
    condition = (
      aws_instance.windows["windows-worker-0"].instance_type == "t3.xlarge"
      && aws_instance.windows["windows-worker-1"].instance_type == "m5.2xlarge"
    )
    error_message = "Windows groups must use their own instance_type and fall back to instance_type_windows."
  }
}

run "rdp_is_attached_to_windows_only" {
  command = plan
  assert {
    condition     = length(aws_security_group.windows_rdp) == 1
    error_message = "windows_enable_rdp must create the RDP security group."
  }
  assert {
    condition = (
      aws_vpc_security_group_ingress_rule.windows_overlay_vpc_vxlan[0].from_port == 4789
      && aws_vpc_security_group_ingress_rule.windows_overlay_vpc_kubelet[0].from_port == 10250
      && length(aws_security_group.windows_overlay[0].ingress) == 0
    )
    error_message = "The overlay SG must hold its overlay/kubelet rules as standalone rules only (no inline ingress), so per-node standalone rules can be added to it safely."
  }
}

run "windows_nodes_admitted_by_ephemeral_sg" {
  command = plan
  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.rke2_windows_node_ingress) == 2
    error_message = "Each Windows node public IP must be admitted by the shared ephemeral SG."
  }
}

run "windows_requires_worker_role" {
  command = plan
  variables {
    nodes = [
      { count = 1, role = ["etcd", "cp", "worker"] },
      { count = 1, role = ["cp"], os = "windows" },
    ]
  }
  expect_failures = [var.nodes]
}

run "windows_rejects_non_rsa_key" {
  command = plan
  variables {
    public_ssh_key = "tests/fixtures/nested-worker.pub"
  }
  expect_failures = [aws_instance.windows]
}

run "linux_nodes_keep_master_first_order" {
  command = apply
  variables {
    nodes = [
      { count = 3, role = ["etcd", "cp"] },
      { count = 1, role = ["worker"] },
      { count = 1, role = ["worker"], os = "windows" },
    ]
  }
  assert {
    condition = [
      for n in jsondecode(output.cluster_nodes_json).nodes : n.name
    ] == ["master", "etcd-cp-1", "etcd-cp-2", "worker-0", "windows-worker-0"]
    error_message = "master must stay first so the first-etcd bootstrap pick matches kube_api_host; Windows nodes are appended after Linux."
  }
}

run "overlay_peers_admitted_with_custom_sg" {
  command = plan
  variables {
    aws_security_group = ["sg-0123456789abcdef0"]
  }
  assert {
    condition = (
      length(aws_vpc_security_group_ingress_rule.windows_overlay_vxlan) == 3
      && length(aws_vpc_security_group_ingress_rule.windows_overlay_kubelet) == 3
    )
    error_message = "A caller-supplied SG must still admit every Linux and Windows node on the overlay ports."
  }
}

run "overlay_peer_rules_skipped_with_ephemeral_sg" {
  command = plan
  assert {
    condition     = length(aws_vpc_security_group_ingress_rule.windows_overlay_vxlan) == 0
    error_message = "The ephemeral SG already admits node public IPs; the overlay peer rules must not duplicate it."
  }
}

run "route53_record_kept_when_lb_disabled" {
  command = plan
  variables {
    create_lb = false
    nodes = [
      { count = 3, role = ["etcd", "cp"] },
      { count = 1, role = ["worker"] },
    ]
  }
  assert {
    condition     = length(aws_lb.aws_nlb) == 0 && aws_route53_record.aws_route53.type == "A"
    error_message = "create_lb=false must skip the load balancer but keep the Route53 record (A record to the first control-plane node) that backs the fqdn output."
  }
}
