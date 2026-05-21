output "grafana_service_name" {
  description = "Grafana ClusterIP service name — use in: kubectl port-forward -n monitoring svc/<this> 3000:80"
  value       = "prometheus-grafana"
}

output "prometheus_service_name" {
  description = "Prometheus ClusterIP service name — use in: kubectl port-forward -n monitoring svc/<this> 9090:9090"
  value       = "prometheus-kube-prometheus-prometheus"
}

output "namespace" {
  description = "Namespace where Prometheus and Grafana are deployed"
  value       = "monitoring"
}

output "port_forward_commands" {
  description = "Copy-paste commands to access Grafana and Prometheus locally"
  value = {
    grafana    = "kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80"
    prometheus = "kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090"
  }
}
