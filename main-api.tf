locals {
  app_name_and_env = "${var.app_name}-${data.terraform_remote_state.common.outputs.app_env}"
  app_env          = data.terraform_remote_state.common.outputs.app_env
}

/*
 * Create ECR repo
 */
module "ecr" {
  source              = "github.com/silinternational/terraform-modules//aws/ecr?ref=3.6.2"
  repo_name           = local.app_name_and_env
  ecsInstanceRole_arn = data.terraform_remote_state.common.outputs.ecsInstanceRole_arn
  ecsServiceRole_arn  = data.terraform_remote_state.common.outputs.ecsServiceRole_arn
  cd_user_arn         = data.terraform_remote_state.common.outputs.codeship_arn
}

/*
 * Create target group for ALB
 */
resource "aws_alb_target_group" "tg" {
  name = replace(
    "tg-${local.app_name_and_env}",
    "/(.{0,32})(.*)/",
    "$1",
  )
  port                 = "3000"
  protocol             = var.disable_tls == "true" ? "HTTP" : "HTTPS"
  vpc_id               = data.terraform_remote_state.common.outputs.vpc_id
  deregistration_delay = "30"

  health_check {
    path     = "/status"
    matcher  = "204"
    protocol = var.disable_tls == "true" ? "HTTP" : "HTTPS"
  }
}

/*
 * Create listener rule for hostname routing to new target group
 */
resource "aws_alb_listener_rule" "tg" {
  listener_arn = data.terraform_remote_state.common.outputs.alb_https_listener_arn
  priority     = "742"

  action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.tg.arn
  }

  condition {
    host_header {
      values = ["${var.subdomain_api}.${var.cloudflare_domain}"]
    }
  }
}

/*
 * Create cloudwatch log group for app logs
 */
resource "aws_cloudwatch_log_group" "cover" {
  name              = local.app_name_and_env
  retention_in_days = 14

  tags = {
    app_name = var.app_name
    app_env  = local.app_env
  }
}

/*
 * Create required passwords
 */
resource "random_id" "db_password" {
  byte_length = 16
}

/*
 * Create new rds instance
 */
module "rds" {
  source              = "github.com/silinternational/terraform-modules//aws/rds/mariadb?ref=3.6.2"
  app_name            = var.app_name
  app_env             = local.app_env
  engine              = "postgres"
  instance_class      = var.db_instance_class
  storage_encrypted   = var.db_storage_encrypted
  db_name             = var.db_database
  db_root_user        = var.db_user
  db_root_pass        = random_id.db_password.hex
  subnet_group_name   = data.terraform_remote_state.common.outputs.db_subnet_group_name
  availability_zone   = data.terraform_remote_state.common.outputs.aws_zones[0]
  security_groups     = [data.terraform_remote_state.common.outputs.vpc_default_sg_id]
  deletion_protection = var.db_deletion_protection
}

/*
 * Create user to interact with S3, SES, and DynamoDB (for CertMagic)
 */
resource "aws_iam_user" "cover" {
  name = local.app_name_and_env
}

resource "aws_iam_access_key" "attachments" {
  user = aws_iam_user.cover.name
}

resource "aws_iam_user_policy" "cover" {
  user = aws_iam_user.cover.name

  policy = <<EOM
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "SendEmail",
      "Effect": "Allow",
      "Action":[
        "ses:SendEmail",
        "ses:SendRawEmail"
      ],
      "Resource": "*"
    },
    {
      "Sid": "DynamoDB",
      "Effect": "Allow",
      "Action":[
        "dynamodb:ConditionCheck",
        "dynamodb:DeleteItem",
        "dynamodb:GetItem",
        "dynamodb:PutItem",
        "dynamodb:Query",
        "dynamodb:Scan",
        "dynamodb:UpdateItem"
      ],
      "Resource": "arn:aws:dynamodb:*:*:table/CertMagic"
    }
  ]
}
EOM

}

locals {
  bucket_policy = templatefile("${path.module}/attachment-bucket-policy.json",
    {
      bucket_name = var.aws_s3_bucket
      user_arn    = aws_iam_user.cover.arn
    }
  )
}

resource "aws_s3_bucket" "attachments" {
  bucket = var.aws_s3_bucket
  acl    = "private"
  policy = local.bucket_policy

  tags = {
    Name     = var.aws_s3_bucket
    app_name = var.app_name
    app_env  = local.app_env
  }
}

/*
 * Create task definition template
 */
locals {
  task_def = templatefile("${path.module}/task-def-api.json",
    {
      GO_ENV                              = var.go_env
      cpu                                 = var.cpu
      memory                              = var.memory
      docker_image                        = module.ecr.repo_url
      docker_tag                          = var.docker_tag
      APP_ENV                             = local.app_env
      DATABASE_URL                        = "postgres://${var.db_user}:${random_id.db_password.hex}@${module.rds.address}:5432/${var.db_database}?sslmode=disable"
      HOST                                = "https://${var.subdomain_api}.${var.cloudflare_domain}"
      AWS_REGION                          = var.aws_region
      AWS_S3_BUCKET                       = var.aws_s3_bucket
      AWS_ACCESS_KEY_ID                   = aws_iam_access_key.attachments.id
      AWS_SECRET_ACCESS_KEY               = aws_iam_access_key.attachments.secret
      EMAIL_FROM_ADDRESS                  = var.email_from_address
      EMAIL_SERVICE                       = var.email_service
      log_group                           = aws_cloudwatch_log_group.cover.name
      region                              = var.aws_region
      log_stream_prefix                   = local.app_name_and_env
      LOG_LEVEL                           = var.log_level
      DISABLE_TLS                         = var.disable_tls
      CERT_DOMAIN_NAME                    = "${var.subdomain_api}.${var.cloudflare_domain}"
      API_BASE_URL                        = "https://${var.subdomain_api}.${var.cloudflare_domain}"
      APP_NAME                            = var.app_name_user
      APP_NAME_LONG                       = var.app_name_long
      SAML_SP_ENTITY_ID                   = var.saml_sp_entity_id
      SAML_IDP_ENTITY_ID                  = var.saml_idp_entity_id
      SAML_IDP_CERT                       = var.saml_idp_cert
      SAML_SP_CERT                        = var.saml_sp_cert
      SAML_SP_PRIVATE_KEY                 = var.saml_sp_private_key
      SAML_ASSERTION_CONSUMER_SERVICE_URL = var.saml_assertion_consumer_service_url
      SAML_SSO_URL                        = var.saml_sso_url
      SAML_SLO_URL                        = var.saml_slo_url
      SAML_CHECK_RESPONSE_SIGNING         = var.saml_check_response_signing
      SAML_SIGN_REQUEST                   = var.saml_sign_request
      SAML_REQUIRE_ENCRYPTED_ASSERTION    = var.saml_require_encrypted_assertion
      ROLLBAR_SERVER_ROOT                 = var.rollbar_server_root
      ROLLBAR_TOKEN                       = var.rollbar_token
      SESSION_SECRET                      = var.session_secret
      UI_URL                              = var.ui_url
      SUPPORT_EMAIL                       = var.support_email
      SANDBOX_EMAIL_ADDRESS               = var.sandbox_email_address
      DYNAMO_DB_TABLE                     = var.dynamo_db_table
      CLOUDFLARE_TOKEN                    = var.cloudflare_token
      CLAIM_INCOME_ACCOUNT                = var.claim_income_account
      EXPENSE_ACCOUNT                     = var.expense_account
      FISCAL_START_MONTH                  = var.fiscal_start_month
      HOUSEHOLD_ID_LOOKUP_URL             = var.household_id_lookup_url
      HOUSEHOLD_ID_LOOKUP_USERNAME        = var.household_id_lookup_username
      HOUSEHOLD_ID_LOOKUP_PASSWORD        = var.household_id_lookup_password
      USER_WELCOME_EMAIL_INTRO            = var.user_welcome_email_intro
      USER_WELCOME_EMAIL_PREVIEW_TEXT     = var.user_welcome_email_preview_text
      USER_WELCOME_EMAIL_ENDING           = var.user_welcome_email_ending
    }
  )
}

/*
 * Create new ecs service
 */
module "ecsapi" {
  source             = "github.com/silinternational/terraform-modules//aws/ecs/service-only?ref=3.6.2"
  cluster_id         = data.terraform_remote_state.common.outputs.ecs_cluster_id
  service_name       = "${var.app_name}-api"
  service_env        = local.app_env
  container_def_json = local.task_def
  desired_count      = var.desired_count
  tg_arn             = aws_alb_target_group.tg.arn
  lb_container_name  = "buffalo"
  lb_container_port  = "3000"
  ecsServiceRole_arn = data.terraform_remote_state.common.outputs.ecsServiceRole_arn
}

/*
 * Create Cloudflare DNS record
 */
resource "cloudflare_record" "dns" {
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = var.subdomain_api
  value   = data.terraform_remote_state.common.outputs.alb_dns_name
  type    = "CNAME"
  proxied = true
}

data "cloudflare_zones" "domain" {
  filter {
    name        = var.cloudflare_domain
    lookup_type = "exact"
    status      = "active"
  }
}

module "adminer" {
  source                 = "silinternational/adminer/aws"
  version                = "1.0.0"
  adminer_default_server = module.rds.address
  adminer_design         = var.adminer_design
  adminer_plugins        = var.adminer_plugins
  app_name               = var.app_name
  app_env                = local.app_env
  cpu                    = 128
  vpc_id                 = data.terraform_remote_state.common.outputs.vpc_id
  alb_https_listener_arn = data.terraform_remote_state.common.outputs.alb_https_listener_arn
  alb_listener_priority  = 733
  subdomain              = "${var.subdomain_api}-adminer"
  cloudflare_domain      = var.cloudflare_domain
  ecs_cluster_id         = data.terraform_remote_state.common.outputs.ecs_cluster_id
  ecsServiceRole_arn     = data.terraform_remote_state.common.outputs.ecsServiceRole_arn
  alb_dns_name           = data.terraform_remote_state.common.outputs.alb_dns_name
  enable                 = var.enable_adminer
}
