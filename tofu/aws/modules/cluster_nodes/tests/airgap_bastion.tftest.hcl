# Contract tests for the optional bastion and the airgap outputs.
# Run from the module dir: tofu init -backend=false && tofu test
# Providers are mocked, so no AWS credentials or resources are involved.

mock_provider "aws" {
  mock_data "aws_subnet" {
    defaults = { assign_ipv6_address_on_creation = false }
  }
  # The QA subnets have no explicit association: the lookup falls back to the VPC main table.
  mock_data "aws_route_tables" {
    defaults = { ids = [] }
  }
  # The airgap precondition reads the effective route table; an IGW-only table is the QA layout.
  mock_data "aws_route_table" {
    defaults = {
      routes = [{ carrier_gateway_id = "", cidr_block = "0.0.0.0/0", core_network_arn = "", destination_prefix_list_id = "", egress_only_gateway_id = "", gateway_id = "igw-00000000", instance_id = "", ipv6_cidr_block = "", local_gateway_id = "", nat_gateway_id = "", network_interface_id = "", odb_network_arn = "", transit_gateway_id = "", vpc_endpoint_id = "", vpc_peering_connection_id = "" }]
    }
  }
}
mock_provider "random" {}

variables {
  public_ssh_key      = "./tests/fixtures/id_ed25519.pub"
  aws_region          = "us-east-2"
  aws_ami             = "ami-00000000000000000"
  aws_hostname_prefix = "dsf-test-k3s-abcde"
  aws_route53_zone    = "qa.rancher.space"
  aws_ssh_user        = "ubuntu"
  aws_security_group  = ["sg-00000000000000000"]
  aws_vpc             = "vpc-00000000"
  aws_subnet          = "subnet-00000000"
  aws_volume_size     = "50"
  aws_volume_type     = "gp3"
  instance_type       = "t3a.medium"
  nodes = [
    { count = 1, role = ["etcd", "cp", "worker"] },
    { count = 1, role = ["worker"] },
  ]
}

run "default_has_no_bastion_and_schema_v2" {
  command = apply

  assert {
    condition     = length(aws_instance.bastion) == 0
    error_message = "bastion must not exist unless bastion.enabled = true"
  }
  assert {
    condition     = jsondecode(output.cluster_nodes_json).metadata.schema_version == 2
    error_message = "cluster_nodes_json must declare schema_version 2"
  }
  assert {
    condition     = jsondecode(output.cluster_nodes_json).bastion == null
    error_message = "bastion must be null in cluster_nodes_json when disabled"
  }
  assert {
    condition     = jsondecode(output.cluster_nodes_json).metadata.airgap == false
    error_message = "metadata.airgap must be false by default"
  }
  assert {
    condition     = length(jsondecode(output.cluster_nodes_json).nodes) == 2
    error_message = "nodes[] must list every instance"
  }
  assert {
    condition     = alltrue([for n in jsondecode(output.cluster_nodes_json).nodes : n.instance_id != "" && n.private_ip != ""])
    error_message = "nodes[] must carry instance_id and private_ip"
  }
  assert {
    condition     = output.bastion_public_dns == null && output.bastion_public_ip == null
    error_message = "bastion outputs must be null when disabled"
  }
  assert {
    condition     = aws_instance.node["master"].associate_public_ip_address == true
    error_message = "connected clusters keep public IPs"
  }
}

run "airgap_requires_bastion" {
  command = plan

  variables {
    airgap_setup = true
  }

  expect_failures = [aws_instance.node]
}

run "airgap_with_bastion" {
  command = apply

  variables {
    airgap_setup = true
    run_id       = "k3s-tarball-qainfra-7-abc123"
    qa_infra_sha = "0123456789abcdef0123456789abcdef01234567"
    arch         = "arm64"
    bastion = {
      enabled       = true
      instance_type = "t4g.large"
    }
  }

  assert {
    condition     = length(aws_instance.bastion) == 1 && aws_instance.bastion[0].associate_public_ip_address == true
    error_message = "airgap needs exactly one bastion with a public IP"
  }
  assert {
    condition     = aws_instance.bastion[0].instance_type == "t4g.large" && aws_instance.bastion[0].ami == var.aws_ami
    error_message = "bastion overrides instance_type and inherits the node AMI by default"
  }
  assert {
    condition     = alltrue([for n in aws_instance.node : n.associate_public_ip_address == false])
    error_message = "airgap nodes must not get a public IP"
  }
  assert {
    condition     = output.kube_api_host == aws_instance.node["master"].private_ip
    error_message = "kube_api_host must be the master private IP in airgap"
  }
  # instance_public_ips is compact()ed; the mocked provider still fabricates a
  # public_ip for associate_public_ip_address=false, so it cannot be asserted here.
  assert {
    condition     = jsondecode(output.cluster_nodes_json).metadata.airgap == true
    error_message = "metadata.airgap must reflect airgap_setup"
  }
  assert {
    condition     = jsondecode(output.cluster_nodes_json).metadata.run_id == "k3s-tarball-qainfra-7-abc123"
    error_message = "metadata.run_id must echo var.run_id"
  }
  assert {
    condition     = jsondecode(output.cluster_nodes_json).metadata.qa_infra_sha == var.qa_infra_sha
    error_message = "metadata.qa_infra_sha must echo the pinned commit"
  }
  assert {
    condition     = jsondecode(output.cluster_nodes_json).metadata.arch == "arm64"
    error_message = "metadata.arch must echo var.arch"
  }
  assert {
    condition     = jsondecode(output.cluster_nodes_json).bastion.public_dns == aws_instance.bastion[0].public_dns
    error_message = "bastion.public_dns must be exported for the registry hostname"
  }
  assert {
    condition     = jsondecode(output.cluster_nodes_json).bastion.private_ip == aws_instance.bastion[0].private_ip
    error_message = "bastion.private_ip must be exported"
  }
  assert {
    condition     = output.bastion_public_dns == aws_instance.bastion[0].public_dns
    error_message = "bastion_public_dns output must match the instance"
  }
  assert {
    condition     = aws_instance.node["master"].tags["RunId"] == "k3s-tarball-qainfra-7-abc123" && aws_instance.bastion[0].tags["RunId"] == "k3s-tarball-qainfra-7-abc123"
    error_message = "every created instance must carry the RunId tag for ownership"
  }
  assert {
    condition     = aws_route53_record.aws_route53.records == toset([aws_instance.node["master"].private_ip])
    error_message = "single-cp Route53 record must point at the private IP in airgap"
  }
}

run "run_id_tag_is_optional" {
  command = apply

  assert {
    condition     = !contains(keys(aws_instance.node["master"].tags), "RunId")
    error_message = "without run_id no RunId tag may be added (existing consumers unchanged)"
  }
}

run "arch_is_validated" {
  command = plan

  variables {
    arch = "x86"
  }

  expect_failures = [var.arch]
}

run "airgap_rejects_nat_default_route" {
  command = plan

  variables {
    airgap_setup = true
    bastion      = { enabled = true }
  }

  override_data {
    target = data.aws_route_table.airgap_subnet
    values = {
      routes = [{ carrier_gateway_id = "", cidr_block = "0.0.0.0/0", core_network_arn = "", destination_prefix_list_id = "", egress_only_gateway_id = "", gateway_id = "", instance_id = "", ipv6_cidr_block = "", local_gateway_id = "", nat_gateway_id = "nat-00000000", network_interface_id = "", odb_network_arn = "", transit_gateway_id = "", vpc_endpoint_id = "", vpc_peering_connection_id = "" }]
    }
  }

  expect_failures = [aws_instance.node]
}

run "airgap_rejects_transit_gateway_default_route" {
  command = plan

  variables {
    airgap_setup = true
    bastion      = { enabled = true }
  }

  override_data {
    target = data.aws_route_table.airgap_subnet
    values = {
      routes = [{ carrier_gateway_id = "", cidr_block = "0.0.0.0/0", core_network_arn = "", destination_prefix_list_id = "", egress_only_gateway_id = "", gateway_id = "", instance_id = "", ipv6_cidr_block = "", local_gateway_id = "", nat_gateway_id = "", network_interface_id = "", odb_network_arn = "", transit_gateway_id = "tgw-00000000", vpc_endpoint_id = "", vpc_peering_connection_id = "" }]
    }
  }

  expect_failures = [aws_instance.node]
}

# The QA subnets carry ::/0 -> IGW in their main table; that is harmless while the subnet
# does not hand out IPv6 addresses (us-east-2), and egress when it does (us-west-1 arm).
run "airgap_allows_ipv6_default_route_when_subnet_assigns_no_ipv6" {
  command = plan

  variables {
    airgap_setup = true
    bastion      = { enabled = true }
  }

  override_data {
    target = data.aws_route_table.airgap_subnet
    values = {
      routes = [{ carrier_gateway_id = "", cidr_block = "0.0.0.0/0", core_network_arn = "", destination_prefix_list_id = "", egress_only_gateway_id = "", gateway_id = "igw-00000000", instance_id = "", ipv6_cidr_block = "", local_gateway_id = "", nat_gateway_id = "", network_interface_id = "", odb_network_arn = "", transit_gateway_id = "", vpc_endpoint_id = "", vpc_peering_connection_id = "" }, { carrier_gateway_id = "", cidr_block = "", core_network_arn = "", destination_prefix_list_id = "", egress_only_gateway_id = "", gateway_id = "igw-00000000", instance_id = "", ipv6_cidr_block = "::/0", local_gateway_id = "", nat_gateway_id = "", network_interface_id = "", odb_network_arn = "", transit_gateway_id = "", vpc_endpoint_id = "", vpc_peering_connection_id = "" }]
    }
  }

  assert {
    condition     = length(local.airgap_egress_routes) == 0
    error_message = "an IPv6 default route is not egress for nodes that get no IPv6 address"
  }
}

run "airgap_rejects_subnet_that_assigns_ipv6" {
  command = plan

  variables {
    airgap_setup = true
    bastion      = { enabled = true }
  }

  override_data {
    target = data.aws_subnet.airgap
    values = { assign_ipv6_address_on_creation = true }
  }

  override_data {
    target = data.aws_route_table.airgap_subnet
    values = {
      routes = [{ carrier_gateway_id = "", cidr_block = "0.0.0.0/0", core_network_arn = "", destination_prefix_list_id = "", egress_only_gateway_id = "", gateway_id = "igw-00000000", instance_id = "", ipv6_cidr_block = "", local_gateway_id = "", nat_gateway_id = "", network_interface_id = "", odb_network_arn = "", transit_gateway_id = "", vpc_endpoint_id = "", vpc_peering_connection_id = "" }, { carrier_gateway_id = "", cidr_block = "", core_network_arn = "", destination_prefix_list_id = "", egress_only_gateway_id = "", gateway_id = "igw-00000000", instance_id = "", ipv6_cidr_block = "::/0", local_gateway_id = "", nat_gateway_id = "", network_interface_id = "", odb_network_arn = "", transit_gateway_id = "", vpc_endpoint_id = "", vpc_peering_connection_id = "" }]
    }
  }

  expect_failures = [aws_instance.node]
}
