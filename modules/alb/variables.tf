# VPC where the ALB will be created
variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

# Public subnets where ALB will sit — needs at least 2 AZs
# ALB must be in public subnets to receive internet traffic
variable "public_subnet_ids" {
  description = "Public subnet IDs for ALB"
  type        = list(string)
}

# ALB SG from the security_groups module
# Controls what traffic is allowed into the ALB
variable "alb_sg_id" {
  description = "ALB security group ID"
  type        = string
}

# Used for consistent resource naming
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}

# Controls whether ALB is created
# false = no ALB, no cost (~$16/month saved)
variable "lab_running" {
  description = "Controls whether ALB is created"
  type        = bool
  default     = false
}
