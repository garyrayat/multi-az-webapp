variable "project_name" { type = string }
variable "environment"  { type = string }
variable "aws_region"   { type = string }

variable "lab_running" {
  type    = bool
  default = false
}

variable "alert_emails" {
  description = "Emails to notify when alarms fire"
  type        = list(string)
  default     = []
}

variable "log_retention_days" {
  description = "Days to retain CloudWatch logs — keep low for cost control in lab"
  type        = number
  default     = 7
}

# Passed from ASG module
variable "asg_name" {
  description = "ASG name for CPU alarm dimension"
  type        = string
}

# Passed from ALB module — empty string when lab_running=false
variable "alb_arn_suffix" {
  description = "ALB ARN suffix for CloudWatch dimensions"
  type        = string
  default     = ""
}

variable "target_group_arn_suffix" {
  description = "Target group ARN suffix for CloudWatch dimensions"
  type        = string
  default     = ""
}

# Passed from RDS module — empty string when lab_running=false
variable "db_instance_id" {
  description = "RDS instance identifier for CPU alarm dimension"
  type        = string
  default     = ""
}
