
terraform {
  required_version = ">= 0.14"
  required_providers {
    aws = {
      version = "~> 4.0"
      source  = "hashicorp/aws"
    }
    cloudflare = {
      version = "~> 3.0"
      source  = "cloudflare/cloudflare"
    }
    github = {
      version = "~> 6.0"
      source  = "integrations/github"
    }
    random = {
      version = "~> 3.0"
      source  = "hashicorp/random"
    }
  }
}
