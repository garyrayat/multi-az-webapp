# Project name passed in from root module
# Used to prefix every resource name so resources are identifiable in AWS console
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

# Environment name (prod, staging, dev)
# Combined with project_name to form the name prefix on all resources
variable "environment" {
  description = "Environment name"
  type        = string
}

# The IP address space for the entire VPC
# All subnets must be smaller blocks carved out of this range
variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
}

# Which AZs to deploy into — we use 2 for multi-AZ HA
# If one AZ fails, resources in the other AZ keep the app running
variable "availability_zones" {
  description = "List of AZs (2 for multi-AZ)"
  type        = list(string)
}

# IP ranges for public subnets — one per AZ
# ALB and NAT Gateways live here — they need direct internet access
variable "public_subnet_cidrs" {
  description = "CIDRs for public subnets (ALB + NAT)"
  type        = list(string)
}

# IP ranges for private app subnets — one per AZ
# EC2 instances live here — no direct internet access, outbound via NAT only
variable "private_subnet_cidrs" {
  description = "CIDRs for private app subnets (EC2)"
  type        = list(string)
}

# IP ranges for private DB subnets — one per AZ
# RDS lives here — completely isolated, no internet access in or out
variable "database_subnet_cidrs" {
  description = "CIDRs for private DB subnets (RDS)"
  type        = list(string)
}

# Master cost control toggle
# false = VPC skeleton only (near zero cost)
# true  = NAT Gateways spin up (~$33/month each), full routing enabled
variable "lab_running" {
  description = "Controls whether NAT gateways are created"
  type        = bool
  default     = false
}
