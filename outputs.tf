output "ecr_repo_url" {
  value = module.ecr.repo_url
}

output "db_password" {
  value = random_id.db_password.hex
}

output "ui_url" {
  value = var.ui_url
}

output "api_url" {
  value = "https://${var.subdomain_api}.${var.cloudflare_domain}"
}

output "aws_ses_access_key_id" {
  description = "access key for SES (internal and Auth0), S3 (attachments), and DynamoDB (CertMagic)"
  value       = aws_iam_access_key.attachments.id
}

output "aws_ses_secret_access_key" {
  description = "access key secret for SES (internal and Auth0), S3 (attachments), and DynamoDB (CertMagic)"
  value       = aws_iam_access_key.attachments.secret
  sensitive   = true
}


/*
 * Backup outputs are just here for convenience
 */


output "bkup_key_arn" {
  value = var.enable_db_backup ? module.backup_rds[0].bkup_key_arn : "backup disabled"
}

output "bkup_key_id" {
  value = var.enable_db_backup ? module.backup_rds[0].bkup_key_id : "to enable backup, set enable_db_backup to true"
}

output "bkup_vault_arn" {
  value = var.enable_db_backup ? module.backup_rds[0].bkup_vault_arn : ""
}

output "bkup_cron_schedule" {
  value = var.enable_db_backup ? var.backup_cron_schedule : ""
}

output "backup_notification_events" {
  value = var.enable_db_backup ? join( ", ", var.backup_notification_events) : ""
}
