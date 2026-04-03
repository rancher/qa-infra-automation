variable "public_ssh_key" {} // The corrals public key.  This should be installed on every node.
variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "aws_region" {}
variable "aws_ami" {}
variable "aws_hostname_prefix" {}
variable "aws_route53_zone" {}
variable "aws_ssh_user" {}
variable "aws_security_group" {
    type = list(string)
}
variable "aws_vpc" {}
variable "aws_volume_size" {}
variable "aws_volume_type" {}
variable "aws_subnet" {}
variable "instance_type" {}
variable "nodes" {
  description = "Configuration for product nodes."
  type = list(object({
    count = number
    role  = list(string) # Allow multiple roles per node (e.g., ["etcd", "cp"], ["worker"])
  }))
}
variable "airgap_setup" {}
variable "proxy_setup" {}
