# ALB DNS name — this is the URL you paste in your browser to test the app
# Also used by Route53 to create a friendly domain name alias
output "alb_dns_name" {
  description = "ALB DNS name"
  value       = var.lab_running ? aws_lb.main[0].dns_name : null
}

# ALB ARN — needed by CloudWatch to create alarms on the ALB
output "alb_arn" {
  description = "ALB ARN"
  value       = var.lab_running ? aws_lb.main[0].arn : null
}

# Target group ARN — consumed by ASG module
# ASG needs this to register EC2 instances into the target group
output "target_group_arn" {
  description = "Target group ARN"
  value       = var.lab_running ? aws_lb_target_group.main[0].arn : null
}
