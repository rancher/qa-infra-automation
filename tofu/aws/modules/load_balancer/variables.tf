variable "name" {}
variable "internal" { type = bool }
variable "subnet_id" {}
variable "vpc_id" {}
variable "ports" { type = set(string) }
