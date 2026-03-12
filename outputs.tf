# =============================================================================
# ROOT OUTPUTS — values you need after apply for connecting and debugging
# =============================================================================

output "alb_dns_name" {
  description = "ALB DNS — paste this in browser when lab_running=true"
  value       = module.alb.alb_dns_name
}

output "asg_name" {
  description = "ASG name — use in AWS console to find EC2 instances"
  value       = module.asg.asg_name
}

output "db_endpoint" {
  description = "RDS endpoint — your app connects here (only set when lab_running=true)"
  value       = module.rds.db_endpoint
}

output "db_secret_arn" {
  description = "Secrets Manager ARN — EC2 fetches DB password using this"
  value       = module.rds.secret_arn
}

output "budget_sns_topic" {
  description = "SNS topic ARN for budget alerts"
  value       = module.budget.sns_topic_arn
}

output "cloudwatch_dashboard" {
  description = "CloudWatch dashboard name — view in AWS Console"
  value       = module.cloudwatch.dashboard_name
}

output "alarm_sns_topic" {
  description = "SNS topic ARN for operational alarms"
  value       = module.cloudwatch.alarm_sns_topic_arn
}
