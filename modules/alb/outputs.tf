output "alb_dns_name" {
  value = try(aws_lb.main[0].dns_name, null)
}

output "alb_arn" {
  value = try(aws_lb.main[0].arn, null)
}

# ARN suffix format required by CloudWatch metric dimensions
output "alb_arn_suffix" {
  value = try(aws_lb.main[0].arn_suffix, null)
}

output "target_group_arn" {
  value = try(aws_lb_target_group.main[0].arn, null)
}

# ARN suffix format required by CloudWatch metric dimensions  
output "target_group_arn_suffix" {
  value = try(aws_lb_target_group.main[0].arn_suffix, null)
}
