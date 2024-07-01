
locals {
  tags = merge({
    managed_by = "terraform"
    workspace  = terraform.workspace
  }, var.tags)
  cloudflare_tags = [for k, v in local.tags : "${k}:${v}"]
  email_domain    = split("@", var.email_from_address)[1]

  ui_hostname  = "${var.subdomain_ui}.${var.cloudflare_domain}"
  api_hostname = "${var.subdomain_api}.${var.cloudflare_domain}"
  api_url      = "https://${local.api_hostname}"
}

locals {
  app_name_and_env = "${var.app_name}-${data.terraform_remote_state.common.outputs.app_env}"
  app_env          = data.terraform_remote_state.common.outputs.app_env
  app_environment  = data.terraform_remote_state.common.outputs.app_environment
  name_tag_suffix  = "${var.app_name}-${var.customer}-${local.app_environment}"
  aws_account      = data.aws_caller_identity.this.account_id
}

/*
 * Create ECR repo
 */
module "ecr" {
  source              = "github.com/silinternational/terraform-modules//aws/ecr?ref=8.8.0"
  repo_name           = local.app_name_and_env
  ecsInstanceRole_arn = data.terraform_remote_state.common.outputs.ecsInstanceRole_arn
  ecsServiceRole_arn  = data.terraform_remote_state.common.outputs.ecsServiceRole_arn
  cd_user_arn         = "arn:aws:iam::${local.aws_account}:user/cd-${var.app_name}-stg"
}

/*
 * Create target group for ALB
 */
resource "aws_alb_target_group" "tg" {
  name                 = substr("tg-${local.app_name_and_env}", 0, 32)
  port                 = "3000"
  protocol             = var.disable_tls == "true" ? "HTTP" : "HTTPS"
  vpc_id               = data.terraform_remote_state.common.outputs.vpc_id
  deregistration_delay = "30"

  health_check {
    path     = "/status"
    matcher  = "204"
    protocol = var.disable_tls == "true" ? "HTTP" : "HTTPS"
  }

  tags = {
    name = "alb_target_group-${local.name_tag_suffix}"
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
      values = [local.api_hostname]
    }
  }

  tags = {
    name = "alb_listener_rule-${local.name_tag_suffix}"
  }
}

/*
 * Create cloudwatch log group for app logs
 */
resource "aws_cloudwatch_log_group" "cover" {
  name              = local.app_name_and_env
  retention_in_days = 14

  tags = {
    name = "cloudwatch_log_group-${local.name_tag_suffix}"
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
  source              = "github.com/silinternational/terraform-modules//aws/rds/mariadb?ref=8.8.0"
  app_name            = var.app_name
  app_env             = local.app_env
  engine              = "postgres"
  engine_version      = "13"
  instance_class      = var.db_instance_class
  storage_encrypted   = var.db_storage_encrypted
  db_name             = var.db_database
  db_root_user        = var.db_user
  db_root_pass        = random_id.db_password.hex
  subnet_group_name   = data.terraform_remote_state.common.outputs.db_subnet_group_name
  availability_zone   = data.terraform_remote_state.common.outputs.aws_zones[0]
  security_groups     = [data.terraform_remote_state.common.outputs.vpc_default_sg_id]
  deletion_protection = var.db_deletion_protection
  ca_cert_identifier  = "rds-ca-rsa2048-g1"
}

/*
 * Create user to interact with S3, SES, and SSM
 */
resource "aws_iam_user" "cover" {
  name = local.app_name_and_env

  tags = {
    name = "iam_user-${local.name_tag_suffix}"
  }
}

resource "aws_iam_access_key" "cover" {
  user = aws_iam_user.cover.name
}

resource "aws_iam_user_policy" "cover" {
  user = aws_iam_user.cover.name

  policy = jsonencode(
    {
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "SendEmail"
          Effect = "Allow"
          Action = [
            "ses:SendEmail",
            "ses:SendRawEmail",
          ]
          Resource = "*"
        },
        {
          Sid    = "SSMParameterStore"
          Effect = "Allow"
          Action = [
            "ssm:GetParametersByPath",
            "ssm:GetParameters",
            "ssm:GetParameter",
          ]
          Resource = "arn:aws:ssm:*:${local.aws_account}:parameter/${var.app_name}/*"
        },
      ]
  })
}

data "aws_caller_identity" "this" {}

resource "aws_s3_bucket" "attachments" {
  bucket = var.aws_s3_bucket

  tags = {
    name = "s3_bucket-${local.name_tag_suffix}"
  }
}

resource "aws_s3_bucket_acl" "attachments" {
  bucket = aws_s3_bucket.attachments.id
  acl    = "private"
}

resource "aws_s3_bucket_policy" "attachments" {
  bucket = aws_s3_bucket.attachments.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Sid    = "BucketOwner"
        Effect = "Allow"
        Principal = {
          AWS = aws_iam_user.cover.arn
        }
        Action = [
          "s3:*",
        ]
        Resource = "arn:aws:s3:::${var.aws_s3_bucket}/*"
      },
      {
        Sid    = "PushApiDocs"
        Effect = "Allow",
        Principal = {
          AWS = one(aws_iam_user.cd[*].arn)
        },
        Action   = "s3:PutObject",
        Resource = "arn:aws:s3:::${var.aws_s3_bucket}/api-docs/*",
      },
      {
        Sid       = "PublicReadApiDocs",
        Effect    = "Allow",
        Principal = "*",
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion",
        ],
        Resource = "arn:aws:s3:::${var.aws_s3_bucket}/api-docs/*",
      },
    ])
  })
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
      HOST                                = local.api_url
      AWS_REGION                          = var.aws_region
      AWS_S3_BUCKET                       = var.aws_s3_bucket
      AWS_ACCESS_KEY_ID                   = aws_iam_access_key.cover.id
      AWS_SECRET_ACCESS_KEY               = aws_iam_access_key.cover.secret
      EMAIL_FROM_ADDRESS                  = var.email_from_address
      EMAIL_SERVICE                       = var.email_service
      log_group                           = aws_cloudwatch_log_group.cover.name
      region                              = var.aws_region
      log_stream_prefix                   = local.app_name_and_env
      LOG_LEVEL                           = var.log_level
      DISABLE_TLS                         = var.disable_tls
      API_BASE_URL                        = local.api_url
      APP_NAME                            = var.app_name_user
      APP_NAME_LONG                       = var.app_name_long
      SAML_SP_ENTITY_ID                   = var.saml_sp_entity_id
      SAML_IDP_ENTITY_ID                  = var.saml_idp_entity_id
      SAML_IDP_CERT                       = var.saml_idp_cert
      SAML_IDP_CERT2                      = var.saml_idp_cert2
      SAML_SP_CERT                        = var.saml_sp_cert
      SAML_SP_PRIVATE_KEY                 = var.saml_sp_private_key
      SAML_ASSERTION_CONSUMER_SERVICE_URL = var.saml_assertion_consumer_service_url
      SAML_SSO_URL                        = var.saml_sso_url
      SAML_SLO_URL                        = var.saml_slo_url
      SAML_CHECK_RESPONSE_SIGNING         = var.saml_check_response_signing
      SAML_SIGN_REQUEST                   = var.saml_sign_request
      SAML_REQUIRE_ENCRYPTED_ASSERTION    = var.saml_require_encrypted_assertion
      SENTRY_DSN                          = var.sentry_dsn
      SESSION_SECRET                      = var.session_secret
      UI_URL                              = var.ui_url
      SUPPORT_EMAIL                       = var.support_email
      SUPPORT_URL                         = var.support_url
      FAQ_URL                             = var.faq_url
      SANDBOX_EMAIL_ADDRESS               = var.sandbox_email_address
      CLAIM_INCOME_ACCOUNT                = var.claim_income_account
      EXPENSE_ACCOUNT                     = var.expense_account
      FISCAL_START_MONTH                  = var.fiscal_start_month
      HOUSEHOLD_ID_LOOKUP_URL             = var.household_id_lookup_url
      HOUSEHOLD_ID_LOOKUP_USERNAME        = var.household_id_lookup_username
      HOUSEHOLD_ID_LOOKUP_PASSWORD        = var.household_id_lookup_password
      USER_WELCOME_EMAIL_INTRO            = var.user_welcome_email_intro
      USER_WELCOME_EMAIL_PREVIEW_TEXT     = var.user_welcome_email_preview_text
      USER_WELCOME_EMAIL_ENDING           = var.user_welcome_email_ending
      POLICY_MAX_COVERAGE                 = var.policy_max_coverage
    }
  )
}

/*
 * Create new ecs service
 */
module "ecsapi" {
  source             = "github.com/silinternational/terraform-modules//aws/ecs/service-only?ref=8.8.0"
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
  zone_id = data.cloudflare_zone.this.id
  name    = var.subdomain_api
  value   = data.terraform_remote_state.common.outputs.alb_dns_name
  type    = "CNAME"
  proxied = true
  tags    = local.cloudflare_tags
}

data "cloudflare_zone" "this" {
  name = var.cloudflare_domain
}

module "adminer" {
  source                 = "silinternational/adminer/aws"
  version                = "1.0.2"
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


/*
 * Optionally create an AWS backup of the rds instance
 */
module "backup_rds" {
  count                = var.enable_db_backup ? 1 : 0
  source               = "github.com/silinternational/terraform-modules//aws/backup/rds?ref=8.8.0"
  app_name             = var.app_name
  app_env              = local.app_env
  aws_access_key       = var.aws_access_key
  aws_secret_key       = var.aws_secret_key
  source_arns          = [module.rds.arn]
  backup_cron_schedule = var.backup_cron_schedule
  notification_events  = var.backup_notification_events
  sns_topic_arn        = var.backup_sns_topic_arn
}


/*
 * SES configurations
 */

# TXT record for SPF
resource "cloudflare_record" "ses_spf" {
  name    = local.email_domain
  type    = "TXT"
  zone_id = data.cloudflare_zone.this.id
  value   = "v=spf1 include:amazonses.com -all"
  tags    = local.cloudflare_tags
  comment = "SPF record for email authentication"
}

resource "aws_ses_domain_identity" "this" {
  domain = local.email_domain
}


# DKIM records
resource "aws_ses_domain_dkim" "this" {
  domain = aws_ses_domain_identity.this.domain
}

resource "cloudflare_record" "ses_dkim" {
  count = 3

  name    = "${element(aws_ses_domain_dkim.this.dkim_tokens, count.index)}._domainkey.${local.email_domain}"
  type    = "CNAME"
  zone_id = data.cloudflare_zone.this.id
  value   = "${element(aws_ses_domain_dkim.this.dkim_tokens, count.index)}.dkim.amazonses.com"
  tags    = local.cloudflare_tags
  comment = "DKIM record for email authentication"
}

/*
 * DMARC record
 */
resource "cloudflare_record" "dmarc" {
  name    = "_dmarc.${local.email_domain}"
  type    = "TXT"
  zone_id = data.cloudflare_zone.this.id

  // `p=none` means no filtering on base domain, `sp=reject` means reject all for subdomains
  value = "v=DMARC1; p=none; sp=reject"

  comment = "DMARC record for ${local.email_domain}"
  tags    = local.cloudflare_tags
}

resource "cloudflare_ruleset" "hsts" {
  count = var.hsts_max_age != "0" ? 1 : 0

  zone_id = data.cloudflare_zone.this.id
  name    = "Add HSTS Strict-Transport-Security header"
  kind    = "zone"
  phase   = "http_response_headers_transform"

  rules {
    action = "rewrite"
    action_parameters {
      headers {
        name      = "Strict-Transport-Security"
        operation = "set"
        value     = "max-age=${var.hsts_max_age}"
      }
    }
    expression  = "(http.host eq \"${local.ui_hostname}\") or (http.host eq \"${local.api_hostname}\")"
    description = "HSTS on Cover"
    enabled     = true
  }
}


/*
 * Create CD (Continuous Deployment) User
 */
resource "aws_iam_user" "cd" {
  count = local.app_env == "stg" ? 1 : 0

  name = "cd-${local.app_name_and_env}"
}

resource "aws_iam_access_key" "cd" {
  count = local.app_env == "stg" ? 1 : 0

  user = one(aws_iam_user.cd[*].name)
}

resource "aws_iam_user_policy" "cd" {
  count = local.app_env == "stg" ? 1 : 0

  name   = "cd-${local.app_name_and_env}"
  user   = one(aws_iam_user.cd[*].name)
  policy = var.cd_user_policy
}

resource "github_actions_secret" "aws_access_key_id" {
  count = var.github_repository == "" ? 0 : 1

  repository      = var.github_repository
  secret_name     = "AWS_ACCESS_KEY_ID"
  plaintext_value = one(aws_iam_access_key.cd[*].id)
}

resource "github_actions_secret" "aws_secret_access_key" {
  count = var.github_repository == "" ? 0 : 1

  repository      = var.github_repository
  secret_name     = "AWS_SECRET_ACCESS_KEY"
  plaintext_value = one(aws_iam_access_key.cd[*].secret)
}


/*
 * Get details about the bucket where we should put db backups
 */
data "aws_s3_bucket" "backup" {
  bucket = var.db_backup_s3_bucket
}

/*
 * Create user for putting backup files into the bucket
 */
resource "aws_iam_user" "backup" {
  name = "db-backup-${var.app_name}-${local.app_env}"
}

resource "aws_iam_access_key" "backup" {
  user = aws_iam_user.backup.name
}

resource "aws_iam_user_policy" "backup" {
  name = "S3-DB-Backup"
  user = aws_iam_user.backup.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ],
        Resource = "${data.aws_s3_bucket.backup.arn}/*"
      }
    ]
  })
}

/*
 * Create ECS service container definition
 */
locals {
  task_def_backup = templatefile("${path.module}/task-def-dbbackup.json", {
    app_name              = var.app_name
    aws_region            = var.aws_region
    b2_application_key_id = var.b2_application_key_id
    b2_application_key    = var.b2_application_key
    b2_bucket             = var.b2_bucket
    b2_host               = var.b2_host
    log_group_name        = aws_cloudwatch_log_group.cover.name
    aws_access_key        = aws_iam_access_key.backup.id
    aws_secret_key        = aws_iam_access_key.backup.secret
    cpu                   = var.backup_cpu
    db_name               = var.db_database
    db_options            = var.db_options
    db_host               = module.rds.address
    db_rootpassword       = random_id.db_password.hex
    db_rootuser           = var.db_user
    db_user               = var.db_user
    db_userpassword       = random_id.db_password.hex
    docker_image          = var.db_backup_docker_image
    docker_tag            = var.db_backup_docker_tag
    memory                = var.backup_memory
    s3_bucket             = var.db_backup_s3_bucket
    service_mode          = var.db_backup_service_mode
  })
}

/*
 * Create role for scheduled running of cron task definitions.
 */
resource "aws_iam_role" "ecs_events" {
  name = "ecs_events-${var.app_name}-${local.app_env}-backup"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = ""
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "ecs_events_run_task_with_any_role" {
  name = "ecs_events_run_task_with_any_role"
  role = aws_iam_role.ecs_events.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "ecs:RunTask"
        Resource = "${aws_ecs_task_definition.backup_cron_td.arn_without_revision}:*"
      }
    ])
  })
}

/*
 * Create cron task definition
 */
resource "aws_ecs_task_definition" "backup_cron_td" {
  family                = "${var.app_name}-backup-${local.app_env}"
  container_definitions = local.task_def_backup
  network_mode          = "bridge"
}

/*
 * CloudWatch configuration to start scheduled backup.
 */
resource "aws_cloudwatch_event_rule" "db_backup_event_rule" {
  name        = "${var.app_name}-${local.app_env}-dbbackup"
  description = "Start scheduled database backup"

  schedule_expression = var.db_backup_schedule
}

resource "aws_cloudwatch_event_target" "backup_event_target" {
  target_id = "${var.app_name}-${local.app_env}-dbbackup"
  rule      = aws_cloudwatch_event_rule.db_backup_event_rule.name
  arn       = data.terraform_remote_state.common.outputs.ecs_cluster_id
  role_arn  = aws_iam_role.ecs_events.arn

  ecs_target {
    task_count          = 1
    launch_type         = "EC2"
    task_definition_arn = aws_ecs_task_definition.backup_cron_td.arn
  }
}

/*
 * Get details about the S3 bucket we are backing up
 */
data "aws_s3_bucket" "s3_data_bucket" {
  bucket = var.aws_s3_bucket
}

/*
 * Create user for getting files from the bucket
 */
resource "aws_iam_user" "clone" {
  name = "s3-clone-${var.app_name}-${local.app_env}"
}

resource "aws_iam_access_key" "clone" {
  user = aws_iam_user.clone.name
}

resource "aws_iam_user_policy" "clone" {
  name = "S3-Clone-Backup"
  user = aws_iam_user.clone.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject"
        ],
        Resource = "${data.aws_s3_bucket.s3_data_bucket.arn}/*"
      }
    ]
  })
}

/*
 * Create ECS service container definition
 */
locals {
  task_def_clone = templatefile("${path.module}/task-def-copys3b2.json", {
    app_name              = var.app_name
    aws_access_key        = aws_iam_access_key.backup.id
    aws_secret_key        = aws_iam_access_key.backup.secret
    aws_region            = var.aws_region
    b2_application_key_id = var.b2_application_key_id
    b2_application_key    = var.b2_application_key
    s3_bucket             = var.aws_s3_bucket
    s3_path               = var.s3_path
    b2_bucket             = var.b2_bucket
    b2_path               = var.b2_path
    rclone_arguments      = var.rclone_arguments
    log_group_name        = aws_cloudwatch_log_group.cover.name
    cpu                   = var.backup_cpu
    docker_image          = var.s3_backup_docker_image
    docker_tag            = var.s3_backup_docker_tag
    memory                = var.backup_memory
  })
}

/*
 * Create role for scheduled running of cron task definitions.
 */
resource "aws_iam_role" "rclone_event" {
  name = "rclone_event-${var.app_name}-${local.app_env}-s3copy"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = ""
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy" "rclone_event_run_task_with_any_role" {
  name = "rclone_event_run_task_with_any_role"
  role = aws_iam_role.rclone_event.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      {
        Effect   = "Allow"
        Action   = "iam:PassRole"
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = "ecs:RunTask"
        Resource = "${aws_ecs_task_definition.clone_cron_td.arn_without_revision}:*"
      }
    ])
  })
}

/*
 * Create cron task definition
 */
resource "aws_ecs_task_definition" "clone_cron_td" {
  family                = "${var.app_name}-clone-${local.app_env}"
  container_definitions = local.task_def_clone
  network_mode          = "bridge"
}

/*
 * CloudWatch configuration to start scheduled backup of S3 using rclone.
 */
resource "aws_cloudwatch_event_rule" "s3_clone_event_rule" {
  name        = "${var.app_name}-${local.app_env}-s3clone"
  description = "Start scheduled backup of S3 using rclone"

  schedule_expression = var.s3_clone_schedule
}

resource "aws_cloudwatch_event_target" "clone_event_target" {
  target_id = "${var.app_name}-${local.app_env}-s3clone"
  rule      = aws_cloudwatch_event_rule.s3_clone_event_rule.name
  arn       = data.terraform_remote_state.common.outputs.ecs_cluster_id
  role_arn  = aws_iam_role.rclone_event.arn

  ecs_target {
    task_count          = 1
    launch_type         = "EC2"
    task_definition_arn = aws_ecs_task_definition.clone_cron_td.arn
  }
}
