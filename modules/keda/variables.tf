# =============================================================================
# KEDA MODULE VARIABLES
# =============================================================================

variable "cluster_name" {
  description = "EKS cluster name — used in resource labels"
  type        = string
}

variable "queue_url" {
  description = "Full SQS queue URL for the KEDA ScaledObject trigger"
  type        = string
}

variable "queue_name" {
  description = "SQS queue name — used in resource labels"
  type        = string
}

variable "aws_region" {
  description = "AWS region where the SQS queue lives"
  type        = string
}

variable "app_namespace" {
  description = "Kubernetes namespace for the nginx workload"
  type        = string
  default     = "webapp"
}

variable "project_name" {
  description = "Project name for resource labelling"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}
