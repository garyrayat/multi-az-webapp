output "collector_endpoint_grpc" {
  description = "OTLP gRPC endpoint — use localhost:4317 from same node, or this DNS from other namespaces"
  value       = "otel-collector.monitoring.svc.cluster.local:4317"
}

output "collector_endpoint_http" {
  description = "OTLP HTTP endpoint — used by Lambda and external senders"
  value       = "otel-collector.monitoring.svc.cluster.local:4318"
}

output "namespace" {
  description = "Monitoring namespace where the collector runs"
  value       = kubernetes_namespace.monitoring.metadata[0].name
}
