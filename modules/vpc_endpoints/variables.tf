variable "vpc_id" {
  description = "VPC to deploy endpoints into"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR block — used for endpoint SG ingress rule"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets where interface endpoint ENIs live"
  type        = list(string)
}

variable "private_route_table_ids" {
  description = "Private route tables to attach S3 gateway endpoint"
  type        = list(string)
}

variable "aws_region" {
  description = "AWS region — used to construct service endpoint names"
  type        = string
}

variable "project_name" {
  description = "Project name prefix for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment (dev/staging/prod)"
  type        = string
}

variable "lab_running" {
  description = "Controls whether interface endpoints are deployed (cost control)"
  type        = bool
  default     = false
}
