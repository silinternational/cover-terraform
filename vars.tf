variable "aws_default_region" {
  default = "us-east-1"
}

variable "aws_region" {
  default = "us-east-1"
}

variable "app_name" {
  default = "riskman"
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

variable "tf_remote_common_organization" {
}

variable "tf_remote_common_workspace" {
}

variable "subdomain_api" {
  default = "riskman-api"
}

variable "subdomain_ui" {
  default = "riskman"
}

variable "docker_tag" {
  default = "latest"
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

variable "log_level" {
  description = "Level below which log messages are silenced"
}

variable "disable_tls" {
  description = "Whether or not to disable HTTPS/TLS in container"
  type        = string
  default     = "false"
}

variable "app_name_user" {
  description = "App name used for end-user presentation, e.g. email template"
  default     = "Riskman"
}

variable "saml_sp_entity_id" {
}

variable "saml_idp_entity_id" {
}

variable "saml_idp_cert" {
}

variable "saml_sp_cert" {
}

variable "saml_sp_private_key" {
}

variable "saml_assertion_consumer_service_url" {
}

variable "saml_sso_url" {
}

variable "saml_check_response_signing" {
  default = "true"
}

variable "saml_sign_request" {
  default = "true"
}

variable "saml_require_encrypted_assertion" {
  default = "true"
}

variable "session_secret" {
}

variable "rollbar_server_root" {
    default = "github.com/silinternational/riskman-api"
}

variable "rollbar_token" {
  description = "Rollbar API token. Omit to disable rollbar logging."
  default     = ""
}

variable "ui_url" {
}
