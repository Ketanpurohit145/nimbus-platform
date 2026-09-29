resource "aws_cloudwatch_log_group" "app" {
  name              = "/${var.project_name}/app"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "app_error" {
  name              = "/${var.project_name}/app-error"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "nginx_access" {
  name              = "/${var.project_name}/nginx/access"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "nginx_error" {
  name              = "/${var.project_name}/nginx/error"
  retention_in_days = 7
}

resource "aws_cloudwatch_log_group" "bootstrap" {
  name              = "/${var.project_name}/bootstrap"
  retention_in_days = 7
}
