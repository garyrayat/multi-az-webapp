# VPC ID where all security groups will be created
# Every SG must belong to a VPC
variable "vpc_id" {
  description = "VPC ID to create security groups in"
  type        = string
}

# Used to name all security groups consistently
# e.g. multi-az-webapp-prod-alb-sg
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}
