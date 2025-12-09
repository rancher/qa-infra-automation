variable "bucket_name" {
  type        = string
  description = "S3 bucket name."
}

variable "aws_access_key" {
  type        = string
  sensitive   = true
  description = "AWS access key."
}

variable "aws_secret_key" {
  type        = string
  sensitive   = true
  description = "AWS secret key."
}

variable "aws_region" {
  type        = string
  description = "AWS region."
}

variable "block_public_access" {
  type        = bool
  default     = true
  description = "Enable S3 block public access."
}
