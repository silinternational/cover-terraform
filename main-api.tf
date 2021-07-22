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

  stickiness {
    type = "lb_cookie"
  }

  health_check {
    path     = "/site/status"
    matcher  = "200"
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
resource "aws_cloudwatch_log_group" "riskman" {
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
resource "aws_iam_user" "riskman" {
  name = local.app_name_and_env
}

resource "aws_iam_access_key" "attachments" {
  user = aws_iam_user.riskman.name
}

resource "aws_iam_user_policy" "riskman" {
  user = aws_iam_user.riskman.name

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
      "Resource": "arn:aws:dynamodb:::table/CertMagic"
    }
  ]
}
EOM

}

data "template_file" "bucket_policy" {
  template = file("${path.module}/attachment-bucket-policy.json")

  vars = {
    bucket_name = var.aws_s3_bucket
    user_arn    = aws_iam_user.riskman.arn
  }
}

resource "aws_s3_bucket" "attachments" {
  bucket = var.aws_s3_bucket
  acl    = "private"
  policy = data.template_file.bucket_policy.rendered

  tags = {
    Name     = var.aws_s3_bucket
    app_name = var.app_name
    app_env  = local.app_env
  }
}

/*
 * Create task definition template
 */
data "template_file" "task_def_api" {
  template = file("${path.module}/task-def-api.json")

  vars = {
    GO_ENV                = var.go_env
    cpu                   = var.cpu
    memory                = var.memory
    docker_image          = module.ecr.repo_url
    docker_tag            = var.docker_tag
    APP_ENV               = local.app_env
    DATABASE_URL          = "postgres://${var.db_user}:${random_id.db_password.hex}@${module.rds.address}:5432/${var.db_database}?sslmode=disable"
    UI_URL                = var.ui_url
    HOST                  = "https://${var.subdomain_api}.${var.cloudflare_domain}"
    AWS_DEFAULT_REGION    = var.aws_default_region
    AWS_S3_BUCKET         = var.aws_s3_bucket
    AWS_ACCESS_KEY_ID     = aws_iam_access_key.attachments.id
    AWS_SECRET_ACCESS_KEY = aws_iam_access_key.attachments.secret
    SESSION_SECRET        = var.session_secret
    SUPPORT_EMAIL         = var.support_email
    EMAIL_FROM_ADDRESS    = var.email_from_address
    EMAIL_SERVICE         = var.email_service
    log_group             = aws_cloudwatch_log_group.riskman.name
    region                = var.aws_default_region
    log_stream_prefix     = local.app_name_and_env
    ROLLBAR_TOKEN         = var.rollbar_token
    LOG_LEVEL             = var.log_level
    DISABLE_TLS           = var.disable_tls
    CERT_DOMAIN_NAME      = "${var.subdomain_api}.${var.cloudflare_domain}"
    APP_NAME              = var.app_name_user
  }
}

/*
 * Create new ecs service
 */
module "ecsapi" {
  source             = "github.com/silinternational/terraform-modules//aws/ecs/service-only?ref=3.6.2"
  cluster_id         = data.terraform_remote_state.common.outputs.ecs_cluster_id
  service_name       = "${var.app_name}-api"
  service_env        = local.app_env
  container_def_json = data.template_file.task_def_api.rendered
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

/******
 *  Adminer service
 */
resource "aws_alb_target_group" "adminer" {
  name = replace(
    "tg-${var.app_name}-adminer-${local.app_env}",
    "/(.{0,32})(.*)/",
    "$1",
  )
  port                 = "8080"
  protocol             = "HTTP"
  vpc_id               = data.terraform_remote_state.common.outputs.vpc_id
  deregistration_delay = "30"

  stickiness {
    type = "lb_cookie"
  }

  health_check {
    path    = "/"
    matcher = "200"
  }
}

/*
 * Create listener rule for hostname routing to new target group
 */
resource "aws_alb_listener_rule" "adminer" {
  listener_arn = data.terraform_remote_state.common.outputs.alb_https_listener_arn
  priority     = "729"

  action {
    type             = "forward"
    target_group_arn = aws_alb_target_group.adminer.arn
  }

  condition {
    host_header {
      values = ["${var.subdomain_api}-adminer.${var.cloudflare_domain}"]
    }
  }
}

/*
 * Create task definition template for Postgres Adminer
 */
data "template_file" "task_def_adminer" {
  template = file("${path.module}/task-def-adminer.json")

  vars = {
    cpu                    = "128"
    memory                 = "128"
    docker_image           = "adminer"
    docker_tag             = "latest"
    ADMINER_DEFAULT_SERVER = module.rds.address
  }
}

/*
 * Create new ecs service
 */
module "ecsadminer" {
  source             = "github.com/silinternational/terraform-modules//aws/ecs/service-only?ref=3.6.2"
  cluster_id         = data.terraform_remote_state.common.outputs.ecs_cluster_id
  service_name       = "${var.app_name}-adminer"
  service_env        = local.app_env
  container_def_json = data.template_file.task_def_adminer.rendered
  desired_count      = var.enable_adminer
  tg_arn             = aws_alb_target_group.adminer.arn
  lb_container_name  = "adminer"
  lb_container_port  = "8080"
  ecsServiceRole_arn = data.terraform_remote_state.common.outputs.ecsServiceRole_arn
}

/*
 * Create Cloudflare DNS record
 */
resource "cloudflare_record" "adminer" {
  count   = var.enable_adminer
  zone_id = data.cloudflare_zones.domain.zones[0].id
  name    = "${var.subdomain_api}-adminer"
  value   = data.terraform_remote_state.common.outputs.alb_dns_name
  type    = "CNAME"
  proxied = true
}