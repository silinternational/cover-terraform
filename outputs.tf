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
