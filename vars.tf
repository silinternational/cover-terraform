variable "aws_region" {
  default = "us-east-1"
}

variable "app_name" {
  default = "cover"
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

variable "adminer_design" {
  default     = ""
  description = "specify Adminer theme, see https://adminer.org/en#extras for options"
}

variable "adminer_plugins" {
  default     = ""
  description = "add Adminer plugins, see https://hub.docker.com/_/adminer/ for details"
}

variable "aws_access_key" {
  default = null
}

variable "aws_secret_key" {
  default = null
}

variable "aws_s3_bucket" {
}

variable "cloudflare_token" {
  description = "Limited access token to manage DNS and Transform Rules"
  type        = string
  default     = null
  sensitive   = true
}

variable "cloudflare_domain" {
}

variable "email_from_address" {
}

variable "email_service" {
}

variable "go_env" {
}

variable "sentry_dsn" {
  description = "Sentry DSN for error logging. Omit to disable Sentry logging."
  default     = ""
}

variable "tf_remote_common_organization" {
}

variable "tf_remote_common_workspace" {
}

variable "subdomain_api" {
  default = "cover-api"
}

variable "subdomain_ui" {
  default = "cover"
}

variable "docker_tag" {
  default = "latest"
}

variable "alerts_email_enabled" {
  default = "true"
}

variable "db_database" {
  default = "cover"
}

variable "db_user" {
  default = "cover"
}

variable "db_instance_class" {
  default = "db.t3.micro"
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
  default     = "Cover"
}

variable "app_name_long" {
  description = "Longer app name used for end-user presentation, e.g. email from name"
  default     = "Cover by SIL"
}

variable "saml_sp_entity_id" {
}

variable "saml_idp_entity_id" {
}

variable "saml_idp_cert" {
  description = "IdP public certificate for SAML authentication"
  type        = string
  default     = ""
}

variable "saml_idp_cert2" {
  description = "Alternate IdP public certificate for SAML authentication. Typically used for updating to a new cert."
  type        = string
  default     = ""
}

variable "saml_sp_cert" {
}

variable "saml_sp_private_key" {
}

variable "saml_assertion_consumer_service_url" {
}

variable "saml_sso_url" {
}

variable "saml_slo_url" {
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

variable "ui_url" {
}

variable "support_email" {
}

variable "support_url" {
  description = "URL for where users can request support"
  default     = ""
}

variable "faq_url" {
  description = "URL of the FAQ page"
  default     = ""
}

variable "sandbox_email_address" {
  description = "email address override to use as the override in a non-production environment"
  default     = ""
}

variable "claim_income_account" {
}

variable "expense_account" {
}

variable "fiscal_start_month" {
  default = 10
}

variable "household_id_lookup_url" {
}

variable "household_id_lookup_username" {
}

variable "household_id_lookup_password" {
}

variable "user_welcome_email_intro" {
  description = "Comment about transition from old system to new system with links"
  type        = string
  default     = ""
}

variable "user_welcome_email_preview_text" {
  description = "Comment about transition from old system to new system without links"
  type        = string
  default     = ""
}

variable "user_welcome_email_ending" {
  description = "Comment about new contact information"
  type        = string
  default     = ""
}

variable "enable_db_backup" {
  description = "Whether to have a database backup or not"
  type        = bool
  default     = false
}

variable "backup_cron_schedule" {
  default = "21 1 * * ? *" # Every day at 01:21 UTC
}

variable "backup_notification_events" {
  description = "The names of the backup events that should trigger an email notification"
  type        = list(string)
  default     = ["BACKUP_JOB_STARTED", "BACKUP_JOB_COMPLETED", "BACKUP_JOB_FAILED", "RESTORE_JOB_COMPLETED"]
}

variable "backup_sns_topic_arn" {
  description = "The ARN of the SNS topic for database backup process notifications"
  type        = string
  default     = ""
}

variable "customer" {
  description = "Customer name, used in AWS tags"
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "policy_max_coverage" {
  description = "The maximum coverage amount for a single policy, in US Dollars."
  type        = number
  default     = 50000
}

variable "hsts_max_age" {
  description = "Set a non-zero value to add a Cloudflare Transform Rule to set an HSTS header with the given max-age"
  type        = string
  default     = "0"
}
