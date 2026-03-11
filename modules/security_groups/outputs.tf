# ALB SG ID consumed by ALB module
output "alb_sg_id" {
  description = "ALB security group ID"
  value       = aws_security_group.alb.id
}

# App SG ID consumed by ASG module
output "app_sg_id" {
  description = "App security group ID"
  value       = aws_security_group.app.id
}

# DB SG ID consumed by RDS module
output "db_sg_id" {
  description = "DB security group ID"
  value       = aws_security_group.db.id
}
