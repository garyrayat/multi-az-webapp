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

output "eks_cluster_name" {
  description = "EKS cluster name (null when enable_eks=false)"
  value       = var.lab_running && var.enable_eks ? module.eks[0].cluster_name : null
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint (null when enable_eks=false)"
  value       = var.lab_running && var.enable_eks ? module.eks[0].cluster_endpoint : null
}

output "sqs_queue_url" {
  description = "SQS queue URL for KEDA event source — send messages here to trigger scaling"
  value       = var.lab_running && var.enable_eks ? module.sqs[0].queue_url : null
}
