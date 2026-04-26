output "alarm_sns_topic_arn" {
  description = "SNS topic ARN for operational alarms"
  value       = aws_sns_topic.alarms.arn
}

output "app_log_group_name" {
  description = "CloudWatch log group for app logs — use in EC2 CloudWatch agent config"
  value       = aws_cloudwatch_log_group.app.name
}

output "nginx_log_group_name" {
  description = "CloudWatch log group for nginx logs"
  value       = aws_cloudwatch_log_group.nginx.name
}

output "dashboard_name" {
  description = "Dashboard name — find it in AWS Console → CloudWatch → Dashboards"
  value       = try(aws_cloudwatch_dashboard.main[0].dashboard_name, null)
}
