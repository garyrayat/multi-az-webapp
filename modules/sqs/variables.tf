# =============================================================================
# SQS MODULE VARIABLES
# =============================================================================

variable "queue_name" {
  description = "Base name for the SQS queue (project/environment prefix is added automatically)"
  type        = string
}

variable "node_role_arn" {
  description = "EKS node IAM role ARN — granted send/receive permissions on the queue"
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

variable "message_retention_seconds" {
  description = "How long SQS retains undelivered messages (seconds). Default: 4 days."
  type        = number
  default     = 345600
}

variable "visibility_timeout_seconds" {
  description = "How long a received message is hidden from other consumers (seconds). Should be >= your consumer's processing time."
  type        = number
  default     = 30
}

variable "max_receive_count" {
  description = "Number of times a message can be received before being moved to the DLQ"
  type        = number
  default     = 3
}
