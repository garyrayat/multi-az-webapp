# =============================================================================
# RDS MODULE OUTPUTS
# Consumed by: root outputs.tf, app user_data scripts, CloudWatch module
# All outputs use try() to return null safely when lab_running=false
# =============================================================================

output "db_endpoint" {
  description = "RDS connection endpoint — host:port — used by app to connect"
  value       = try(aws_db_instance.main[0].endpoint, null)
}

output "db_address" {
  description = "RDS hostname only (no port) — cleaner for app config"
  value       = try(aws_db_instance.main[0].address, null)
}

output "db_port" {
  description = "PostgreSQL port — always 5432"
  value       = try(aws_db_instance.main[0].port, null)
}

output "db_name" {
  description = "Database name inside PostgreSQL"
  value       = var.db_name
}

output "secret_arn" {
  description = "Secrets Manager ARN — EC2 IAM role fetches credentials using this ARN"
  value       = try(aws_secretsmanager_secret.db[0].arn, null)
}

output "secret_name" {
  description = "Secrets Manager secret name — human readable path"
  value       = try(aws_secretsmanager_secret.db[0].name, null)
}
