output "s3_endpoint_id" {
  description = "S3 Gateway endpoint ID"
  value       = aws_vpc_endpoint.s3.id
}

output "interface_endpoint_ids" {
  description = "Map of interface endpoint IDs keyed by service name"
  value       = { for k, v in aws_vpc_endpoint.interface : k => v.id }
}

output "endpoint_security_group_id" {
  description = "Security group ID attached to interface endpoints"
  value       = aws_security_group.vpc_endpoints.id
}
