variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment (dev/staging/prod)"
  type        = string
}

variable "budget_limit" {
  description = "Monthly budget cap in USD"
  type        = number
  default     = 100
}

variable "warning_threshold" {
  description = "USD amount that triggers WARNING alert"
  type        = number
  default     = 50
}

variable "critical_threshold" {
  description = "USD amount that triggers CRITICAL alert"
  type        = number
  default     = 80
}

variable "alert_emails" {
  description = "Email addresses to notify on budget threshold breach"
  type        = list(string)
}
