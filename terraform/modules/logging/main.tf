# CloudWatch log groups fed by the EC2 CloudWatch Agent (see terraform/modules/ec2/bootstrap.sh); 7-day retention keeps costs low.
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

# Captures cloud-init/user-data output, useful for diagnosing bootstrap.sh failures on first boot.
resource "aws_cloudwatch_log_group" "bootstrap" {
  name              = "/${var.project_name}/bootstrap"
  retention_in_days = 7
}
