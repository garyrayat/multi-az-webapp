# =============================================================================
# ROOT OUTPUTS — values you need after apply for connecting and debugging
# =============================================================================

output "alb_dns_name" {
  description = "ALB DNS — paste this in browser when lab_running=true"
  value       = module.alb.alb_dns_name
}

output "asg_name" {
  description = "ASG name — use in AWS console to find EC2 instances"
  value       = module.asg.asg_name
}

output "db_endpoint" {
  description = "RDS endpoint — your app connects here (only set when lab_running=true)"
  value       = module.rds.db_endpoint
}

output "db_secret_arn" {
  description = "Secrets Manager ARN — EC2 fetches DB password using this"
  value       = module.rds.secret_arn
}

output "budget_sns_topic" {
  description = "SNS topic ARN for budget alerts"
  value       = module.budget.sns_topic_arn
}

output "cloudwatch_dashboard" {
  description = "CloudWatch dashboard name — view in AWS Console"
  value       = module.cloudwatch.dashboard_name
}

output "alarm_sns_topic" {
  description = "SNS topic ARN for operational alarms"
  value       = module.cloudwatch.alarm_sns_topic_arn
}

output "eks_cluster_name" {
  description = "EKS cluster name (null when enable_eks=false)"
  value       = var.lab_running && var.enable_eks ? module.eks[0].cluster_name : null
}

output "eks_cluster_endpoint" {
  description = "EKS API server endpoint (null when enable_eks=false)"
  value       = var.lab_running && var.enable_eks ? module.eks[0].cluster_endpoint : null
}

output "sqs_queue_url" {
  description = "SQS queue URL for KEDA event source — send messages here to trigger scaling"
  value       = var.lab_running && var.enable_eks ? module.sqs[0].queue_url : null
}

output "lambda_function_url" {
  description = "Lambda public function URL — open in browser to trigger credit activity"
  value       = var.enable_lambda ? module.lambda[0].function_url : null
}

output "lambda_function_name" {
  description = "Lambda function name"
  value       = var.enable_lambda ? module.lambda[0].function_name : null
}

# ── Prometheus / Grafana outputs ─────────────────────────────────────────────

output "grafana_port_forward" {
  description = "Run this to access Grafana at http://localhost:3000"
  value       = local.use_eks ? module.prometheus[0].port_forward_commands.grafana : null
}

output "prometheus_port_forward" {
  description = "Run this to access Prometheus at http://localhost:9090"
  value       = local.use_eks ? module.prometheus[0].port_forward_commands.prometheus : null
}

# ── AWS OTEL outputs ──────────────────────────────────────────────────────────

output "otel_collector_grpc" {
  description = "OTLP gRPC endpoint (AWS/EKS) — set OTEL_EXPORTER_OTLP_ENDPOINT in app pods"
  value       = local.use_eks ? module.otel[0].collector_endpoint_grpc : null
}

output "otel_collector_http" {
  description = "OTLP HTTP endpoint (AWS/EKS) — fallback for Lambda and non-gRPC clients"
  value       = local.use_eks ? module.otel[0].collector_endpoint_http : null
}

output "otel_namespace" {
  description = "Kubernetes namespace the AWS OTEL collector DaemonSet runs in"
  value       = local.use_eks ? module.otel[0].namespace : null
}

# ── GKE outputs ───────────────────────────────────────────────────────────────

output "gke_cluster_name" {
  description = "GKE cluster name (null when enable_gke=false)"
  value       = local.use_gke ? module.gke[0].cluster_name : null
}

output "gke_cluster_endpoint" {
  description = "GKE API server endpoint — use in gcloud container clusters get-credentials"
  value       = local.use_gke ? module.gke[0].cluster_endpoint : null
  sensitive   = true
}

output "gke_otel_service_account" {
  description = "GCP SA email for the OTEL collector — annotated on the K8s SA for Workload Identity"
  value       = local.use_gke ? module.gke[0].otel_service_account_email : null
}

# ── GCP OTEL outputs ──────────────────────────────────────────────────────────

output "otel_gcp_collector_grpc" {
  description = "OTLP gRPC endpoint (GCP/GKE) — set OTEL_EXPORTER_OTLP_ENDPOINT in Spring Boot pods"
  value       = local.use_gke ? module.otel_gcp[0].collector_endpoint_grpc : null
}

output "otel_gcp_collector_http" {
  description = "OTLP HTTP endpoint (GCP/GKE) — fallback for non-gRPC clients"
  value       = local.use_gke ? module.otel_gcp[0].collector_endpoint_http : null
}

output "otel_gcp_java_agent_path" {
  description = "Path to OTEL Java agent JAR — set JAVA_TOOL_OPTIONS=-javaagent:<this value> in Spring Boot pod spec"
  value       = local.use_gke ? module.otel_gcp[0].java_agent_volume_mount_path : null
}

output "otel_gcp_namespace" {
  description = "Kubernetes namespace the GCP OTEL collector DaemonSet runs in"
  value       = local.use_gke ? module.otel_gcp[0].namespace : null
}
