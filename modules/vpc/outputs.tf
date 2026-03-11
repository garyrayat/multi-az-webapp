# VPC core identifiers
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}

# Subnet IDs — passed to ALB (public), ASG (private), RDS (database)
output "public_subnet_ids" {
  description = "Public subnet IDs (ALB lives here)"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (EC2 app tier lives here)"
  value       = aws_subnet.private[*].id
}

output "database_subnet_ids" {
  description = "Isolated database subnet IDs (RDS lives here)"
  value       = aws_subnet.database[*].id
}

output "db_subnet_group_name" {
  description = "RDS subnet group name — passed directly to RDS module"
  value       = aws_db_subnet_group.main.name
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs (empty list when lab_running=false)"
  value       = aws_nat_gateway.main[*].id
}

# ✅ NEW — required by vpc_endpoints module for S3 Gateway endpoint
# Gateway endpoints inject entries into route tables, not subnets.
# The S3 endpoint needs every private route table ID so all AZs get coverage.
output "private_route_table_ids" {
  description = "Private route table IDs — used by VPC endpoints module for S3 gateway"
  value       = aws_route_table.private[*].id
}
