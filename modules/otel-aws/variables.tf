variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev / staging / prod)"
  type        = string
}

variable "aws_region" {
  description = "AWS region — used by awsxray and awscloudwatchlogs exporters"
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name — stamped on every span via resource processor"
  type        = string
}
