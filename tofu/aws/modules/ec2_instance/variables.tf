variable "ami" {}
variable "instance_type" {}
variable "subnet_id" {}
variable "security_group_ids" { type = list(string) }
variable "ssh_key_name" {}
variable "volume_size" {}
variable "name" {}
variable "user_id" {}
variable "ssh_key" {}
variable associate_public_ip {}
