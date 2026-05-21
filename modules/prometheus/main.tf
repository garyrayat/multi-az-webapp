# =============================================================================
# PROMETHEUS MODULE — kube-prometheus-stack
#
# Single Helm chart installs:
#   - Prometheus Operator (manages Prometheus + Alertmanager as CRDs)
#   - Prometheus (scrapes metrics from all pods with prometheus.io/scrape=true)
#   - Grafana (dashboards — accessed via kubectl port-forward, no LoadBalancer)
#   - kube-state-metrics (K8s object metrics: pod restarts, deployment replicas)
#   - node-exporter DaemonSet (node-level: CPU, memory, disk per node)
#
# Access Grafana (free, no LoadBalancer):
#   kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
#   open http://localhost:3000  (admin / var.grafana_admin_password)
#
# Access Prometheus:
#   kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
#   open http://localhost:9090
#
# Scrape config wired to OTEL collector:
#   The OTEL DaemonSet pods are annotated with prometheus.io/scrape=true on port 8888.
#   The prometheus-operator PodMonitor (below) picks these up and adds them to the
#   scrape targets — so Grafana shows collector pipeline throughput
#   (otelcol_exporter_sent_spans, otelcol_processor_dropped_metric_points, etc.)
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ─── Namespace ────────────────────────────────────────────────────────────────
# The monitoring namespace is already created by module.otel-aws.
# We reference it here with a data source instead of creating it again —
# Terraform would error if two resources try to own the same namespace.
data "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
  }
}

# ─── kube-prometheus-stack ────────────────────────────────────────────────────
resource "helm_release" "prometheus_stack" {
  name       = "prometheus"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = "~65.0"
  namespace  = data.kubernetes_namespace.monitoring.metadata[0].name

  # Block until all stack pods are Running before Terraform marks this done.
  # Prometheus takes ~60s to start; Grafana takes ~30s.
  wait    = true
  timeout = 600

  # ── Grafana ────────────────────────────────────────────────────────────────
  # ClusterIP only — access via kubectl port-forward, no LoadBalancer needed.
  # adminPassword set here so you don't have to look up the auto-generated secret.
  set {
    name  = "grafana.adminPassword"
    value = var.grafana_admin_password
  }
  set {
    name  = "grafana.service.type"
    value = "ClusterIP"
  }
  # Sidecar watches ConfigMaps with label grafana_dashboard=1 and auto-imports them.
  # This is how the dashboard ConfigMap below gets loaded without a Grafana restart.
  set {
    name  = "grafana.sidecar.dashboards.enabled"
    value = "true"
  }
  set {
    name  = "grafana.sidecar.dashboards.label"
    value = "grafana_dashboard"
  }
  set {
    name  = "grafana.sidecar.dashboards.searchNamespace"
    value = "monitoring"
  }

  # ── Prometheus ────────────────────────────────────────────────────────────
  # ClusterIP — port-forward to 9090 for PromQL queries and rule inspection.
  set {
    name  = "prometheus.service.type"
    value = "ClusterIP"
  }
  # Retain 15 days of metrics on-cluster (default). For prod use remote_write
  # to Thanos / Cortex / Amazon Managed Prometheus instead.
  set {
    name  = "prometheus.prometheusSpec.retention"
    value = "15d"
  }
  # PodMonitor and ServiceMonitor selectors: empty = watch all namespaces.
  # This lets the PodMonitor below (in monitoring ns) pick up OTEL collector pods.
  set {
    name  = "prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues"
    value = "false"
  }
  set {
    name  = "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues"
    value = "false"
  }

  # ── Alertmanager ──────────────────────────────────────────────────────────
  # Disabled for the lab — CloudWatch alarms handle alerting on the AWS side.
  # Enable and configure routes/receivers for a production setup.
  set {
    name  = "alertmanager.enabled"
    value = "false"
  }

  # ── node-exporter ─────────────────────────────────────────────────────────
  # DaemonSet on every node. Exposes /proc and /sys metrics: CPU steal,
  # disk saturation, network errors — things kube-state-metrics doesn't cover.
  set {
    name  = "prometheus-node-exporter.enabled"
    value = "true"
  }

  depends_on = [data.kubernetes_namespace.monitoring]
}

# ─── PodMonitor — OTEL Collector ─────────────────────────────────────────────
# Tells Prometheus to scrape the OTEL collector pods on port 8888.
# The collector exposes its own pipeline metrics there:
#   otelcol_exporter_sent_spans        — spans successfully shipped to X-Ray
#   otelcol_exporter_send_failed_spans — export failures (alert on this)
#   otelcol_processor_dropped_metric_points — batch overflow
#   otelcol_receiver_accepted_spans    — ingest rate
# These are the SLIs for the observability pipeline itself.
resource "kubernetes_manifest" "otel_pod_monitor" {
  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "PodMonitor"
    metadata = {
      name      = "otel-collector"
      namespace = data.kubernetes_namespace.monitoring.metadata[0].name
      labels = {
        # Must match grafana.sidecar.dashboards.label for auto-discovery
        release = "prometheus"
      }
    }
    spec = {
      selector = {
        matchLabels = { app = "otel-collector" }
      }
      podMetricsEndpoints = [{
        port     = "metrics"   # named port 8888 on the DaemonSet
        path     = "/metrics"
        interval = "30s"
      }]
    }
  }

  # CRDs are installed by the helm_release — must wait for them
  depends_on = [helm_release.prometheus_stack]
}

# ─── Grafana Dashboard ConfigMap ──────────────────────────────────────────────
# The Grafana sidecar picks up any ConfigMap in the monitoring namespace that
# has the label grafana_dashboard=1 and imports the JSON as a dashboard.
# No Grafana restart needed — sidecar hot-reloads within ~30s.
#
# Dashboard panels:
#   Row 1 — Application
#     - nginx request rate (from kube-state-metrics + node-exporter proxy)
#     - HTTP 5xx error rate
#   Row 2 — OTEL Pipeline (SLIs for the collector itself)
#     - Spans received vs sent (receiver vs exporter rate)
#     - Export failures (alert threshold at > 0)
#   Row 3 — Infrastructure
#     - EKS node CPU utilisation (node-exporter)
#     - Pod restarts (kube-state-metrics)
resource "kubernetes_config_map" "grafana_dashboard" {
  metadata {
    name      = "${local.name_prefix}-otel-dashboard"
    namespace = data.kubernetes_namespace.monitoring.metadata[0].name
    labels = {
      grafana_dashboard = "1"   # triggers sidecar auto-import
    }
  }

  data = {
    "otel-dashboard.json" = jsonencode({
      title       = "${var.project_name} — OTEL Observability"
      uid         = "otel-observability"
      schemaVersion = 38
      refresh     = "30s"
      time        = { from = "now-1h", to = "now" }

      panels = [
        # ── Panel 0: Spans received by OTEL collector ────────────────────────
        {
          id    = 1
          title = "OTEL — Spans Received/s"
          type  = "timeseries"
          gridPos = { h = 8, w = 12, x = 0, y = 0 }
          targets = [{
            expr         = "rate(otelcol_receiver_accepted_spans_total[2m])"
            legendFormat = "{{receiver}} accepted"
          }, {
            expr         = "rate(otelcol_receiver_refused_spans_total[2m])"
            legendFormat = "{{receiver}} refused"
          }]
          fieldConfig = {
            defaults = { unit = "reqps", color = { mode = "palette-classic" } }
          }
        },

        # ── Panel 1: Spans exported to X-Ray ────────────────────────────────
        {
          id    = 2
          title = "OTEL — Spans Exported/s (X-Ray)"
          type  = "timeseries"
          gridPos = { h = 8, w = 12, x = 12, y = 0 }
          targets = [{
            expr         = "rate(otelcol_exporter_sent_spans_total{exporter=\"awsxray\"}[2m])"
            legendFormat = "sent to X-Ray"
          }, {
            expr         = "rate(otelcol_exporter_send_failed_spans_total{exporter=\"awsxray\"}[2m])"
            legendFormat = "export failures"
          }]
          fieldConfig = {
            defaults = { unit = "reqps", color = { mode = "palette-classic" } }
          }
        },

        # ── Panel 2: Batch processor queue ───────────────────────────────────
        {
          id    = 3
          title = "OTEL — Batch Processor Queue Size"
          type  = "timeseries"
          gridPos = { h = 8, w = 12, x = 0, y = 8 }
          targets = [{
            expr         = "otelcol_processor_batch_batch_size_trigger_send_total"
            legendFormat = "batch sends (size trigger)"
          }, {
            expr         = "otelcol_processor_batch_timeout_trigger_send_total"
            legendFormat = "batch sends (timeout trigger)"
          }]
          fieldConfig = {
            defaults = { unit = "short", color = { mode = "palette-classic" } }
          }
        },

        # ── Panel 3: EKS Node CPU ────────────────────────────────────────────
        {
          id    = 4
          title = "Node CPU Utilisation %"
          type  = "timeseries"
          gridPos = { h = 8, w = 12, x = 12, y = 8 }
          targets = [{
            expr = <<-PROMQL
              100 - (avg by(instance) (rate(node_cpu_seconds_total{mode="idle"}[2m])) * 100)
            PROMQL
            legendFormat = "{{instance}}"
          }]
          fieldConfig = {
            defaults = {
              unit = "percent"
              min  = 0
              max  = 100
              thresholds = {
                mode = "absolute"
                steps = [
                  { color = "green",  value = null },
                  { color = "yellow", value = 60   },
                  { color = "red",    value = 80   },
                ]
              }
            }
          }
        },

        # ── Panel 4: Pod restarts ────────────────────────────────────────────
        {
          id    = 5
          title = "Pod Restarts (all namespaces)"
          type  = "timeseries"
          gridPos = { h = 8, w = 12, x = 0, y = 16 }
          targets = [{
            expr         = "increase(kube_pod_container_status_restarts_total[10m])"
            legendFormat = "{{namespace}}/{{pod}}"
          }]
          fieldConfig = {
            defaults = { unit = "short", color = { mode = "palette-classic" } }
          }
        },

        # ── Panel 5: Export failure rate (SLI alert panel) ───────────────────
        {
          id    = 6
          title = "OTEL Export Failures (should be 0)"
          type  = "stat"
          gridPos = { h = 8, w = 12, x = 12, y = 16 }
          targets = [{
            expr         = "sum(rate(otelcol_exporter_send_failed_spans_total[5m]))"
            legendFormat = "failed span exports/s"
          }]
          fieldConfig = {
            defaults = {
              unit = "reqps"
              thresholds = {
                mode = "absolute"
                steps = [
                  { color = "green", value = null },
                  { color = "red",   value = 0.01 },
                ]
              }
              mappings = []
            }
          }
          options = {
            reduceOptions = { calcs = ["lastNotNull"] }
            colorMode     = "background"
            graphMode     = "none"
          }
        },
      ]
    })
  }

  depends_on = [helm_release.prometheus_stack]
}
