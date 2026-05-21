variable "project_name" {
  description = "Name prefix for all resources and dashboard titles"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev / staging / prod)"
  type        = string
}

variable "grafana_admin_password" {
  description = "Grafana admin password — used to log in at localhost:3000 after port-forward. Store in tfvars, never commit to git."
  type        = string
  sensitive   = true
  default     = "admin"
}
