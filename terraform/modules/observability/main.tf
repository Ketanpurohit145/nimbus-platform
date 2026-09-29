# SNS topic + email subscription only get created if a notification email was actually provided.
resource "aws_sns_topic" "alarms" {
  count = var.notification_email == "" ? 0 : 1
  name  = "${var.project_name}-alarms"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.notification_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.alarms[0].arn
  protocol  = "email"
  endpoint  = var.notification_email
}

locals {
  alarm_actions = var.notification_email == "" ? [] : [aws_sns_topic.alarms[0].arn]
}

# Fires when the EC2 app instance's CPU stays above 80% for one minute (basic overload warning).
resource "aws_cloudwatch_metric_alarm" "ec2_cpu" {
  alarm_name          = "${var.project_name}-ec2-cpu-high"
  alarm_description   = "EC2 CPU utilization above 80% for one one-minute datapoint."
  comparison_operator = "GreaterThanThreshold"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 80
  treat_missing_data  = "missing"
  alarm_actions       = local.alarm_actions
  actions_enabled     = var.notification_email != ""

  dimensions = {
    InstanceId = var.ec2_instance_id
  }
}

# Fires when the RDS instance's CPU stays above 80% for one minute.
resource "aws_cloudwatch_metric_alarm" "rds_cpu" {
  alarm_name          = "${var.project_name}-rds-cpu-high"
  alarm_description   = "RDS CPU utilization above 80% for one one-minute datapoint."
  comparison_operator = "GreaterThanThreshold"
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 80
  treat_missing_data  = "missing"
  alarm_actions       = local.alarm_actions
  actions_enabled     = var.notification_email != ""

  dimensions = {
    DBInstanceIdentifier = var.rds_instance_identifier
  }
}
