# =============================================================================
# OTEL MODULE — AWS
# Deploys the OpenTelemetry Collector as a DaemonSet on EKS.
#
# Why DaemonSet: one collector per node. Apps send to localhost:4317 (hostPort).
# No DNS resolution, no cross-node hop, no single point of failure.
# If the collector pod dies, only that node loses telemetry — not the cluster.
#
# Pipeline:
#   nginx/Lambda → OTLP (gRPC 4317 / HTTP 4318)
#     → k8sattributes (enriches spans with pod/namespace/node metadata)
#     → resource (stamps cluster name + environment)
#     → batch (buffers 256 spans or 1s — reduces X-Ray API calls ~10x)
#     → awsxray (traces) + awscloudwatchlogs (structured logs)
#
# Auth: node IAM instance profile — no static credentials anywhere.
# The EKS node role must have xray:PutTraceSegments and logs:PutLogEvents.
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ─── Namespace ────────────────────────────────────────────────────────────────
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = "monitoring"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "observability"
    }
  }
}

# ─── RBAC — required by k8sattributes processor ───────────────────────────────
# The k8sattributes processor resolves incoming OTLP connection IPs → pod name
# by calling the k8s API. Without GET/LIST/WATCH on pods and namespaces,
# every span arrives with zero k8s context — unfilterable in X-Ray.
resource "kubernetes_service_account" "otel_collector" {
  metadata {
    name      = "otel-collector"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
}

resource "kubernetes_cluster_role" "otel_collector" {
  metadata {
    name = "otel-collector"
  }
  # Minimum permissions for k8sattributes to enrich spans
  rule {
    api_groups = [""]
    resources  = ["pods", "namespaces", "nodes", "endpoints"]
    verbs      = ["get", "list", "watch"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["replicasets", "deployments"]
    verbs      = ["get", "list", "watch"]
  }
}

resource "kubernetes_cluster_role_binding" "otel_collector" {
  metadata { name = "otel-collector" }
  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.otel_collector.metadata[0].name
  }
  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account.otel_collector.metadata[0].name
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }
}

# ─── Collector ConfigMap ──────────────────────────────────────────────────────
# The pipeline definition. This is the core of the module.
resource "kubernetes_config_map" "otel_collector" {
  metadata {
    name      = "otel-collector-config"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
  }

  data = {
    "config.yaml" = <<-YAML
      receivers:
        otlp:
          protocols:
            grpc:
              endpoint: 0.0.0.0:4317   # apps on same node send here via localhost
            http:
              endpoint: 0.0.0.0:4318   # HTTP fallback (Lambda, scripts)

      processors:
        # k8sattributes: resolves source IP → pod → adds k8s.namespace.name,
        # k8s.pod.name, k8s.deployment.name to every span and log record.
        # This is what makes "filter by namespace" work in X-Ray and CloudWatch.
        k8sattributes:
          auth_type: serviceAccount
          passthrough: false
          extract:
            metadata:
              - k8s.namespace.name
              - k8s.pod.name
              - k8s.pod.uid
              - k8s.node.name
              - k8s.deployment.name
          pod_association:
            - sources:
                - from: resource_attribute
                  name: k8s.pod.ip
            - sources:
                - from: connection

        # resource: stamps static attributes on every signal.
        # deployment.environment lets you filter dev/staging/prod in X-Ray.
        resource:
          attributes:
            - key: deployment.environment
              value: "${var.environment}"
              action: upsert
            - key: k8s.cluster.name
              value: "${var.cluster_name}"
              action: upsert
            - key: cloud.provider
              value: "aws"
              action: upsert

        # batch: buffers spans before flushing. Reduces X-Ray PutTraceSegments
        # API calls by ~10x versus sending one span at a time.
        batch:
          timeout: 1s
          send_batch_size: 256

      exporters:
        # awsxray: converts OTLP spans to X-Ray segment JSON.
        # Uses node IAM instance profile — no static credentials.
        # Requires xray:PutTraceSegments + xray:GetSamplingRules on node role.
        awsxray:
          region: ${var.aws_region}

        # awscloudwatchlogs: ships OTLP log records to CloudWatch.
        # Structured JSON fields (trace_id, service.name, log.level) become
        # queryable fields in CloudWatch Insights — zero parser config needed.
        awscloudwatchlogs:
          region: ${var.aws_region}
          log_group_name: /${var.project_name}/${var.environment}/otel
          log_stream_name: collector
          sending_queue:
            enabled: true
            num_consumers: 2
            queue_size: 1000

        # debug: emits one summary line per batch to collector stdout.
        # Visible via: kubectl logs -n monitoring daemonset/otel-collector
        # Remove in prod to avoid log volume.
        debug:
          verbosity: basic

      service:
        telemetry:
          logs:
            level: warn          # collector's own logs — not app telemetry

        pipelines:
          traces:
            receivers:  [otlp]
            processors: [k8sattributes, resource, batch]
            exporters:  [awsxray, debug]

          logs:
            receivers:  [otlp]
            processors: [k8sattributes, resource, batch]
            exporters:  [awscloudwatchlogs]
    YAML
  }

  depends_on = [kubernetes_namespace.monitoring]
}

# ─── DaemonSet ────────────────────────────────────────────────────────────────
# One collector pod per node. hostPort binds 4317/4318 on the node's network
# interface — apps send to localhost:4317 with no service discovery needed.
resource "kubernetes_daemonset" "otel_collector" {
  metadata {
    name      = "otel-collector"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels    = { app = "otel-collector" }
  }

  spec {
    selector {
      match_labels = { app = "otel-collector" }
    }

    template {
      metadata {
        labels = { app = "otel-collector" }
        annotations = {
          # Prometheus scrapes collector's own metrics (pipeline throughput,
          # export success/failure rates) from port 8888.
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8888"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        service_account_name             = kubernetes_service_account.otel_collector.metadata[0].name
        automount_service_account_token  = true

        container {
          name  = "otel-collector"
          # AWS ADOT image — includes awsxray and awscloudwatchlogs exporters.
          # The upstream otel/opentelemetry-collector-contrib image works too
          # but ADOT is AWS-tested and patched for the AWS exporters.
          image = "public.ecr.aws/aws-observability/aws-otel-collector:v0.40.0"
          args  = ["--config=/conf/config.yaml"]

          # OTLP gRPC — primary ingest. hostPort exposes on node network.
          port {
            name           = "otlp-grpc"
            container_port = 4317
            host_port      = 4317
            protocol       = "TCP"
          }
          # OTLP HTTP — used by Lambda (sends via HTTP, not node localhost)
          port {
            name           = "otlp-http"
            container_port = 4318
            host_port      = 4318
            protocol       = "TCP"
          }
          # Collector self-metrics — scraped by Prometheus
          port {
            name           = "metrics"
            container_port = 8888
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "200Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "500Mi"
            }
          }

          volume_mount {
            name       = "otel-config"
            mount_path = "/conf"
          }

          # Health check extension on 13133 — standard ADOT/OTEL health endpoint
          liveness_probe {
            http_get {
              path = "/"
              port = 13133
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            failure_threshold     = 3
          }

          readiness_probe {
            http_get {
              path = "/"
              port = 13133
            }
            initial_delay_seconds = 5
            period_seconds        = 10
          }
        }

        volume {
          name = "otel-config"
          config_map {
            name = kubernetes_config_map.otel_collector.metadata[0].name
          }
        }

        # Tolerate master/control-plane nodes — ensures coverage if running
        # on clusters where control plane is accessible (uncommon on EKS)
        toleration {
          key      = "node-role.kubernetes.io/master"
          operator = "Exists"
          effect   = "NoSchedule"
        }
      }
    }
  }

  depends_on = [
    kubernetes_config_map.otel_collector,
    kubernetes_cluster_role_binding.otel_collector,
  ]
}

# ─── ClusterIP Service ────────────────────────────────────────────────────────
# Fallback for pods that send by DNS (e.g. Lambda via VPC endpoint, or pods
# that don't know their node IP). Pods on the same node should use localhost.
resource "kubernetes_service" "otel_collector" {
  metadata {
    name      = "otel-collector"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    labels    = { app = "otel-collector" }
  }
  spec {
    selector = { app = "otel-collector" }
    type     = "ClusterIP"
    port {
      name        = "otlp-grpc"
      port        = 4317
      target_port = 4317
      protocol    = "TCP"
    }
    port {
      name        = "otlp-http"
      port        = 4318
      target_port = 4318
      protocol    = "TCP"
    }
    port {
      name        = "metrics"
      port        = 8888
      target_port = 8888
      protocol    = "TCP"
    }
  }
}
