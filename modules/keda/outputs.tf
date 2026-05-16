output "keda_namespace" {
  description = "Kubernetes namespace where KEDA is installed"
  value       = kubernetes_namespace.keda.metadata[0].name
}

output "webapp_namespace" {
  description = "Kubernetes namespace for the nginx workload"
  value       = kubernetes_namespace.webapp.metadata[0].name
}

output "nginx_service_node_port" {
  description = "NodePort that nginx is exposed on — must match ALB target group port (30080)"
  value       = 30080
}
