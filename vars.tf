variable "aws_default_region" {
  default = "us-east-1"
}

variable "aws_region" {
  default = "us-east-1"
}

variable "app_name" {
  default = "riskman"
}

variable "app_name_user" {
  description = "App name used for end-user presentation, e.g. email template"
  default     = "Riskman"
}

variable "memory" {
  default = "128"
}

variable "cpu" {
  default = "200"
}

variable "desired_count" {
  default = 2
}

variable "enable_adminer" {
  default     = 0
  description = "1 = enable adminer, 0 = disable adminer"
}

variable "aws_access_key" {
}

variable "aws_secret_key" {
}

variable "aws_s3_bucket" {
}

variable "cloudflare_token" {
  description = "Limited access token for DNS updates"
}

variable "cloudflare_domain" {
}

variable "email_from_address" {
}

variable "email_service" {
}

variable "go_env" {
}

variable "rollbar_token" {
  description = "Rollbar API token. Omit to disable rollbar logging."
  default     = ""
}

variable "session_secret" {
}

variable "subdomain_ui_dns_name" {
  description = "Used as value sent to cloudflare for dns record, separate var from subdomain_ui so that in prod we can pass @"
}

variable "tf_remote_common" {
}

variable "subdomain_api" {
  default = "riskman-api"
}

variable "docker_tag" {
  default = "latest"
}

variable "admin_email" {
  default = "gtis_appsdev@groups.sil.org"
}

variable "alerts_email" {
  default = "gtis_appsdev@groups.sil.org"
}

variable "support_email" {
  default = "gtis_appsdev@groups.sil.org"
}

variable "alerts_email_enabled" {
  default = "true"
}

variable "db_database" {
  default = "riskman"
}

variable "db_user" {
  default = "riskman"
}

variable "db_instance_class" {
  default = "db.t2.micro"
}

variable "db_storage_encrypted" {
  default = "false"
}

variable "db_deletion_protection" {
  default = "false"
}

variable "ui_url" {
}

variable "log_level" {
  description = "Level below which log messages are silenced"
}

variable "disable_tls" {
  description = "Whether or not to disable HTTPS/TLS in container"
  type        = string
  default     = "false"
}
