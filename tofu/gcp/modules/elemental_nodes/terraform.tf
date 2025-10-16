terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0" # use a versão mais recente estável
    }
  }

  required_version = ">= 1.6.0"
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
  credentials = file(var.service_account_key_path)
}
