# =============================================================================
# RDS MODULE VARIABLES
# =============================================================================

variable "project_name" {
  description = "Project name prefix for all resource names"
  type        = string
}

variable "environment" {
  description = "Environment (dev/staging/prod)"
  type        = string
}

variable "lab_running" {
  description = "Controls whether RDS is deployed — false saves ~$15/month"
  type        = bool
  default     = false
}

# --- Network (passed from VPC + security_groups modules) ---
variable "db_subnet_group_name" {
  description = "RDS subnet group — lives in isolated DB subnets, not app subnets"
  type        = string
}

variable "db_sg_id" {
  description = "Security group ID — only allows inbound 5432 from app SG"
  type        = string
}

# --- Database config ---
variable "db_instance_class" {
  description = "RDS instance size — db.t3.micro = free tier eligible"
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Name of the initial database created inside PostgreSQL"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master username — password is auto-generated, never in tfvars"
  type        = string
  default     = "dbadmin"
}

variable "multi_az" {
  description = "Enable Multi-AZ standby replica — doubles cost, use for prod only"
  type        = bool
  default     = false
}
