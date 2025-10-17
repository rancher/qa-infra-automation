variable "cluster_name" {
  type     = string
}

variable fqdn {
  type = string
}

variable api_key {
  type = string
}

variable insecure {
    default = true
    type    = bool
}
