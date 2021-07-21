
terraform {
  required_version = ">= 0.14"
  required_providers {
    aws = {
      version = "3.12.0"
      source  = "hashicorp/aws"
    }
    cloudflare = {
      version = "~> 2.0"
      source  = "cloudflare/cloudflare"
    }
    random = {
      version = "~> 2.3"
      source  = "hashicorp/random"
    }
    template = {
      version = "~> 2.1"
      source  = "hashicorp/template"
    }
  }
}
