variable "user_id" {} // how the user is identified (usually github username)
variable "ssh_key" {} // SSH Key file
variable "ssh_key_name" {} // SSH Key name
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
variable "aws_subnet" {}
variable "instance_type" {}
