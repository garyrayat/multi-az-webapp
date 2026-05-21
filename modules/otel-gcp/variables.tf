variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev / staging / prod)"
  type        = string
}

variable "gcp_project_id" {
  description = "GCP project ID — required by googlecloudtrace and googlecloud exporters to route telemetry to the correct project"
  type        = string
}

variable "gcp_service_account_email" {
  description = "GCP service account email used for Workload Identity annotation. Must have roles/cloudtrace.agent, roles/logging.logWriter, roles/monitoring.metricWriter"
  type        = string
}

variable "cluster_name" {
  description = "GKE cluster name — stamped on every span via resource processor"
  type        = string
}
