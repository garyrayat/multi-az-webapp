# =============================================================================
# ROOT MODULE VARIABLES
# =============================================================================

# --- Core Config ---
variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "multi-az-webapp"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

# --- Lab Cost Control ---
variable "lab_running" {
  description = "true = full stack deployed | false = near-zero cost (destroys NAT/ALB/EC2)"
  type        = bool
  default     = false
}

# --- Network ---
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs to deploy across — determines subnet count"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (one per AZ) — ALB lives here"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (one per AZ) — EC2 app tier lives here"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "database_subnet_cidrs" {
  description = "Database subnet CIDRs (one per AZ) — RDS lives here"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

# --- Compute ---
variable "instance_type" {
  description = "EC2 instance type for app servers"
  type        = string
  default     = "t3.micro"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

# --- Governance / Tagging ---
variable "owner" {
  description = "Owner name/email — appears in cost reports and resource tags"
  type        = string
  default     = "garry"
}

variable "cost_center" {
  description = "Finance cost center code — used in AWS Cost Explorer allocation"
  type        = string
  default     = "engineering"
}

# --- Budget & Alerting ---
variable "budget_limit" {
  description = "Monthly AWS spend cap in USD — alerts sent before this is hit"
  type        = number
  default     = 100
}

variable "alert_emails" {
  description = "Emails to notify on budget threshold breach — must confirm subscription"
  type        = list(string)
  default     = []
}
