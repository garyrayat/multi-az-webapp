# =============================================================================
# EKS MODULE VARIABLES
# =============================================================================

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for EKS cluster"
  type        = string
  default     = "1.31"
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS worker nodes (t3.medium minimum — t3.micro too small for kubelet)"
  type        = string
  default     = "t3.small"
}

variable "desired_nodes" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "min_nodes" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 1
}

variable "max_nodes" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 4
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for EKS worker nodes"
  type        = list(string)
}

variable "app_sg_id" {
  description = "Security group ID to attach to worker nodes (allows ALB → port 30080)"
  type        = string
}

variable "target_group_arn" {
  description = "ALB target group ARN — EKS node group ASG is attached here so ALB can route to nodes"
  type        = string
}

variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name"
  type        = string
}
