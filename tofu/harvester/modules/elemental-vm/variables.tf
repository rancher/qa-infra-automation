variable "image_namespace" {
  type        = string
  description = "Image namespace"
}

variable "image_url" {
  type        = string
  description = "Source image URL"
}

variable "namespace" {
  type        = string
  description = "Kubernetes namespace"
}

variable "cpu" {
  type        = number
  description = "Number of vCPUs"
}

variable "memory" {
  type        = string
  description = "Memory size"
}

variable "user_data_base64" {
  type        = string
  description = "Base64-encoded user data"
}

variable "disk_size" {
  type        = string
  description = "Disk size"
}
