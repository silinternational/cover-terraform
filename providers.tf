provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key

  default_tags {
    tags = merge({
      file       = path.module
      managed_by = "terraform"
      workspace  = terraform.workspace
    }, var.tags)
  }
}

provider "cloudflare" {
  api_token = var.cloudflare_token
}
