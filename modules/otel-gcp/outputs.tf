output "collector_endpoint_grpc" {
  description = "OTLP gRPC endpoint — Spring Boot pods set OTEL_EXPORTER_OTLP_ENDPOINT to this value, or use localhost:4317 on the same node via hostPort"
  value       = "otel-collector.monitoring.svc.cluster.local:4317"
}

output "collector_endpoint_http" {
  description = "OTLP HTTP endpoint — fallback for clients that don't support gRPC"
  value       = "otel-collector.monitoring.svc.cluster.local:4318"
}

output "namespace" {
  description = "Monitoring namespace where the collector runs"
  value       = kubernetes_namespace.monitoring.metadata[0].name
}

output "java_agent_volume_mount_path" {
  description = "Path where the OTEL Java agent JAR is available — set JAVA_TOOL_OPTIONS=-javaagent:<this path>/opentelemetry-javaagent.jar in Spring Boot pod spec"
  value       = "/otel/opentelemetry-javaagent.jar"
}
