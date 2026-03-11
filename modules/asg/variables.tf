# Used for consistent resource naming
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

# Private subnets where EC2 instances will be launched
# ASG spreads instances across these subnets — one per AZ
variable "private_subnet_ids" {
  description = "Private subnet IDs for EC2 instances"
  type        = list(string)
}

# App SG from security_groups module
# Controls what traffic EC2 instances accept
variable "app_sg_id" {
  description = "App security group ID"
  type        = string
}

# Instance profile from IAM module
# Gives EC2 instances access to SSM, CloudWatch, Secrets Manager
variable "instance_profile_name" {
  description = "IAM instance profile name"
  type        = string
}

# Target group from ALB module
# ASG registers instances here so ALB can route traffic to them
variable "target_group_arn" {
  description = "ALB target group ARN"
  type        = string
}

# EC2 instance size — t2.micro is free tier eligible
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t2.micro"
}

# Controls whether instances are running
# false = 0 instances, no cost
variable "lab_running" {
  description = "Controls ASG capacity"
  type        = bool
  default     = false
}
