variable "region" {
  description = "AWS region to deploy into."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where resources are placed."
  type        = string
}

variable "subnet_for_bastion" {
  description = "The AWS subnet where to create the bastion server, enables both IPv4 and IPv6 addresses."
  type        = string
}

variable "subnet_for_rke2_servers" {
  description = "The AWS subnet where to create the instances of the RKE2 cluster, enables only IPv6 addresses."
  type        = string
}

variable "existing_key_name" {
  description = "The name of your existing AWS key pair for SSH access to the bastion server."
  type        = string
}

variable "private_key_path" {
  description = "Absolute path to the SSH private key in your local machine, used to ssh to the bastion server."
  type        = string
}

variable "server_count" {
  description = "The number of server nodes of the RKE2 cluster."
  type        = number
  default     = 3
}

variable "prefix" {
  description = "A unique prefix for all resources created by this module (e.g., 'jiaqi-tf')."
  type        = string
}

variable "rke2_version" {
  description = "The k8s version of the RKE2 cluster."
  type        = string
  default     = "v1.28.5+rke2r1" # Updated to a more recent version
}

variable "rke2_token" {
  description = "A secret token for nodes to join the cluster."
  type        = string
  sensitive   = true
}

variable "rke2_cni" {
  description = "CNI for RKE2 (e.g., 'calico', 'cilium')."
  type        = string
  default     = "calico"
}

variable "rke2_cluster_cidr" {
  description = "Cluster CIDR (IPv6). For dual-stack, comma-separate v4,v6."
  type        = string
  default     = "2001:cafe:42::/56"
}

variable "rke2_service_cidr" {
  description = "Service CIDR (IPv6). For dual-stack, comma-separate v4,v6."
  type        = string
  default     = "2001:cafe:43::/112"
}

variable "rancher_chart_repo" {
  description = "The Helm chart repository for Rancher."
  default     = "https://releases.rancher.com/server-charts/latest"
}

variable "cert_manager_version" {
  description = "Cert-manager chart version."
  type        = string
  default     = "v1.15.1" # Using a more recent patch
}

variable "cert_type" {
  description = "Certificate type for Rancher ingress. Options: self-signed, lets-encrypt."
  default     = "self-signed"
}

variable "rancher_chart_version" {
  description = "The version of the Rancher Helm chart to deploy."
  default     = "2.8.3" # Using a more recent version
}

variable "rancher_image" {
  description = "The container image for Rancher."
  default     = "rancher/rancher"
}

variable "rancher_image_tag" {
  description = "The tag for the Rancher container image."
  default     = "v2.8.3" # Corresponds to chart version
}

variable "lets_encrypt_email" {
  description = "Email address for Let's Encrypt registration if cert_type is 'lets-encrypt'."
  default     = "you@email.com"
}

variable "bootstrap_password" {
  description = "Bootstrap password for the Rancher admin user."
  type        = string
  sensitive   = true
}

variable "rancher_hostname" {
  description = "The FQDN for the Rancher UI (e.g., rancher.example.com)."
  type        = string
}

variable "route53_zone_name" {
  description = "The name of the Route 53 public hosted zone to create the DNS record in."
  type        = string
}
