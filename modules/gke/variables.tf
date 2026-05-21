variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "environment" {
  description = "Deployment environment (dev / staging / prod)"
  type        = string
}

variable "gcp_project_id" {
  description = "GCP project ID — used for all resource creation and IAM bindings"
  type        = string
}

variable "gcp_region" {
  description = "GCP region for the GKE cluster and node pool (e.g., us-central1). Regional clusters replicate the control plane across 3 zones — equivalent to EKS multi-AZ."
  type        = string
  default     = "us-central1"
}

variable "cluster_name" {
  description = "GKE cluster name"
  type        = string
}

variable "network" {
  description = "VPC network name or self_link — GKE cluster is placed in this network"
  type        = string
  default     = "default"
}

variable "subnetwork" {
  description = "Subnetwork name or self_link for GKE nodes — equivalent to private_subnet_ids in EKS"
  type        = string
  default     = "default"
}

variable "node_machine_type" {
  description = "GCE machine type for worker nodes. e2-standard-2 (2 vCPU, 8 GB) is the GCP equivalent of t3.small for light workloads."
  type        = string
  default     = "e2-standard-2"
}

variable "desired_nodes" {
  description = "Initial node count per zone"
  type        = number
  default     = 1
}

variable "min_nodes" {
  description = "Minimum node count per zone (autoscaling floor)"
  type        = number
  default     = 1
}

variable "max_nodes" {
  description = "Maximum node count per zone (autoscaling ceiling)"
  type        = number
  default     = 4
}
