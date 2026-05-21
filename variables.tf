# =============================================================================
# ROOT MODULE VARIABLES
# =============================================================================

# --- Core Config ---
variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "multi-az-webapp"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  default     = "dev"
}

# --- Lab Cost Control ---
variable "lab_running" {
  description = "true = full stack deployed | false = near-zero cost (destroys NAT/ALB/EC2)"
  type        = bool
  default     = false
}

# --- Network ---
variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "AZs to deploy across — determines subnet count"
  type        = list(string)
  default     = ["us-east-1a", "us-east-1b"]
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs (one per AZ) — ALB lives here"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "private_subnet_cidrs" {
  description = "Private subnet CIDRs (one per AZ) — EC2 app tier lives here"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "database_subnet_cidrs" {
  description = "Database subnet CIDRs (one per AZ) — RDS lives here"
  type        = list(string)
  default     = ["10.0.20.0/24", "10.0.21.0/24"]
}

# --- Compute ---
variable "instance_type" {
  description = "EC2 instance type for app servers"
  type        = string
  default     = "t3.micro"
}

variable "db_instance_class" {
  description = "RDS instance class"
  type        = string
  default     = "db.t3.micro"
}

# --- Governance / Tagging ---
variable "owner" {
  description = "Owner name/email — appears in cost reports and resource tags"
  type        = string
  default     = "garry"
}

variable "cost_center" {
  description = "Finance cost center code — used in AWS Cost Explorer allocation"
  type        = string
  default     = "engineering"
}

# --- Budget & Alerting ---
variable "budget_limit" {
  description = "Monthly AWS spend cap in USD — alerts sent before this is hit"
  type        = number
  default     = 100
}

variable "alert_emails" {
  description = "Emails to notify on budget threshold breach — must confirm subscription"
  type        = list(string)
  default     = []
}

# --- RDS ---
variable "db_name" {
  description = "PostgreSQL database name"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "dbadmin"
}

variable "multi_az" {
  description = "Enable RDS Multi-AZ standby — doubles DB cost, prod only"
  type        = bool
  default     = false
}

# --- EKS / KEDA ---

variable "enable_eks" {
  description = "true = use EKS + KEDA instead of EC2/ASG. Requires lab_running=true."
  type        = bool
  default     = false
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.31"
}

variable "eks_node_instance_type" {
  description = "EC2 instance type for EKS worker nodes (t3.medium minimum)"
  type        = string
  default     = "t3.small"
}

variable "eks_desired_nodes" {
  description = "Desired number of EKS worker nodes"
  type        = number
  default     = 2
}

# --- Lambda ---

variable "enable_lambda" {
  description = "Deploy Lambda function with public function URL (AWS credit activity)"
  type        = bool
  default     = false
}

# --- Prometheus / Grafana ---

variable "grafana_admin_password" {
  description = "Grafana admin password — access at localhost:3000 after kubectl port-forward"
  type        = string
  sensitive   = true
  default     = "admin"
}

# --- GKE / GCP ---

variable "enable_gke" {
  description = "true = deploy GKE cluster + OTEL-GCP stack. Mirrors enable_eks but targets GCP."
  type        = bool
  default     = false
}

variable "gcp_project_id" {
  description = "GCP project ID for all Google resources (GKE, Cloud Trace, Cloud Logging)"
  type        = string
  default     = ""
}

variable "gcp_region" {
  description = "GCP region for GKE cluster (e.g., us-central1)"
  type        = string
  default     = "us-central1"
}

variable "gke_node_machine_type" {
  description = "GCE machine type for GKE worker nodes — e2-standard-2 is roughly equivalent to t3.small"
  type        = string
  default     = "e2-standard-2"
}

variable "gke_desired_nodes" {
  description = "Initial number of GKE nodes per zone"
  type        = number
  default     = 1
}
