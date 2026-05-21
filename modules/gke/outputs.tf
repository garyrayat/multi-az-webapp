output "cluster_name" {
  description = "GKE cluster name — use in gcloud container clusters get-credentials"
  value       = google_container_cluster.main.name
}

output "cluster_endpoint" {
  description = "GKE control plane endpoint — used by the kubernetes provider in provider.tf"
  value       = google_container_cluster.main.endpoint
  sensitive   = true
}

output "cluster_ca_certificate" {
  description = "Base64-encoded cluster CA — used by the kubernetes provider to verify the API server TLS cert"
  value       = google_container_cluster.main.master_auth[0].cluster_ca_certificate
  sensitive   = true
}

output "node_service_account_email" {
  description = "Email of the GKE node GCP SA — used for auditing and IAM inspection"
  value       = google_service_account.node.email
}

output "otel_service_account_email" {
  description = "Email of the OTEL Collector GCP SA — pass to otel-gcp module as gcp_service_account_email. This SA has cloudtrace.agent + logging.logWriter + monitoring.metricWriter and is bound to the K8s SA monitoring/otel-collector via Workload Identity."
  value       = google_service_account.otel_collector.email
}
