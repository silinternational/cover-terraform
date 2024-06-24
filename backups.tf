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
  name = "db-backup-${var.app_name}-${data.terraform_remote_state.common.outputs.app_env}"
}

resource "aws_iam_access_key" "backup" {
  user = aws_iam_user.backup.name
}

resource "aws_iam_user_policy" "backup" {
  name = "S3-DB-Backup"
  user = aws_iam_user.backup.name

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject"
      ],
      "Resource": "${data.aws_s3_bucket.backup.arn}/db-backups/${data.terraform_remote_state.common.outputs.app_env}/*"
    }
  ]
}
EOF

}

/*
 * Create ECS service container definition
 */
locals {
  task_def_backup = templatefile("${path.module}/task-def-backup.json", {
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
  name = "ecs_events-${var.app_name}-${data.terraform_remote_state.common.outputs.app_env}-backup"

  assume_role_policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "",
            "Effect": "Allow",
            "Principal": {
              "Service": "events.amazonaws.com"
            },
            "Action": "sts:AssumeRole"
        }
    ]
}
EOF

}

resource "aws_iam_role_policy" "ecs_events_run_task_with_any_role" {
  name = "ecs_events_run_task_with_any_role"
  role = aws_iam_role.ecs_events.id

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": "iam:PassRole",
            "Resource": "*"
        },
        {
            "Effect": "Allow",
            "Action": "ecs:RunTask",
            "Resource": "${replace(aws_ecs_task_definition.backup_cron_td.arn, "/:\\d+$/", ":*")}"
        }
    ]
}
EOF

}

/*
 * Create cron task definition
 */
resource "aws_ecs_task_definition" "backup_cron_td" {
  family                = "${var.app_name}-backup-${data.terraform_remote_state.common.outputs.app_env}"
  container_definitions = local.task_def_backup
  network_mode          = "bridge"
}

/*
 * CloudWatch configuration to start scheduled backup.
 */
resource "aws_cloudwatch_event_rule" "event_rule" {
  name        = "${var.app_name}-${data.terraform_remote_state.common.outputs.app_env}-backup"
  description = "Start scheduled backup"

  schedule_expression = var.db_backup_schedule
}

resource "aws_cloudwatch_event_target" "backup_event_target" {
  target_id = "${var.app_name}-${data.terraform_remote_state.common.outputs.app_env}-backup"
  rule      = aws_cloudwatch_event_rule.event_rule.name
  arn       = data.terraform_remote_state.common.outputs.ecs_cluster_id
  role_arn  = aws_iam_role.ecs_events.arn

  ecs_target {
    task_count          = 1
    launch_type         = "EC2"
    task_definition_arn = aws_ecs_task_definition.backup_cron_td.arn
  }
}

