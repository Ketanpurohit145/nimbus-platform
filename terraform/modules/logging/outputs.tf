output "log_group_names" {
  value = {
    app          = aws_cloudwatch_log_group.app.name
    app_error    = aws_cloudwatch_log_group.app_error.name
    nginx_access = aws_cloudwatch_log_group.nginx_access.name
    nginx_error  = aws_cloudwatch_log_group.nginx_error.name
    bootstrap    = aws_cloudwatch_log_group.bootstrap.name
  }
}

output "log_group_arns" {
  value = [
    aws_cloudwatch_log_group.app.arn,
    aws_cloudwatch_log_group.app_error.arn,
    aws_cloudwatch_log_group.nginx_access.arn,
    aws_cloudwatch_log_group.nginx_error.arn,
    aws_cloudwatch_log_group.bootstrap.arn
  ]
}
