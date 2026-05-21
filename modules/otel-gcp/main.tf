# =============================================================================
# OTEL MODULE — GCP
# Same DaemonSet pattern as the AWS module. Only the exporters and auth change.
#
# App stack: Java Spring Boot on GKE, Cloud SQL (PostgreSQL), Pub/Sub, Cassandra
#
# Why the pipeline is identical but the exporters differ:
#   AWS: awsxray (traces)        + awscloudwatchlogs (logs)
#   GCP: googlecloudtrace (traces) + googlecloud (logs + metrics)
#
# Auth: Workload Identity — GKE ServiceAccount annotated with a GCP service
# account that has cloudtrace.agent + logging.logWriter + monitoring.metricWriter.
# Zero static credentials. Same security posture as IRSA on EKS.
#
# Java Spring Boot instrumentation:
#   The OTEL Java agent (-javaagent:/otel/opentelemetry-javaagent.jar) is injected
#   via the Deployment's initContainer or the pod's JAVA_TOOL_OPTIONS env var.
#   It auto-instruments:
#     - Spring MVC / servlet (HTTP spans)
#     - JDBC → Cloud SQL (every SQL query becomes a span with db.statement)
#     - Google Cloud Pub/Sub client (messaging spans, propagates traceparent in attributes)
#     - DataStax Cassandra driver (db.system=cassandra, db.cassandra.table)
#   No code changes to the Spring Boot app. Zero-code instrumentation.
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

# ─── Workload Identity — GCP equivalent of IRSA ───────────────────────────────
# GKE maps this k8s ServiceAccount to a GCP service account via annotation.
# The collector pods inherit GCP credentials without any mounted secrets.
# GCP SA must have: roles/cloudtrace.agent, roles/logging.logWriter,
#                   roles/monitoring.metricWriter
resource "kubernetes_service_account" "otel_collector" {
  metadata {
    name      = "otel-collector"
    namespace = kubernetes_namespace.monitoring.metadata[0].name
    annotations = {
      # This annotation is what activates Workload Identity on GKE.
      # Format: {gcp_project}.svc.id.goog[{k8s_namespace}/{k8s_sa}]
      "iam.gke.io/gcp-service-account" = var.gcp_service_account_email
    }
  }
}

# ─── RBAC — same as AWS, required by k8sattributes processor ──────────────────
resource "kubernetes_cluster_role" "otel_collector" {
  metadata {
    name = "otel-collector"
  }
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
              endpoint: 0.0.0.0:4317
            http:
              endpoint: 0.0.0.0:4318

      processors:
        # k8sattributes — identical to AWS module.
        # Enriches every span from the Java agent with k8s.namespace.name,
        # k8s.pod.name, k8s.deployment.name — queryable in Cloud Trace filters.
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

        # resource: GCP-specific attributes for Cloud Trace and Cloud Logging.
        # gcp.project_id is required by the googlecloudtrace exporter to route
        # traces to the correct GCP project. cloud.platform tells Cloud Trace
        # this is a GKE workload — enables GKE-specific trace UI features.
        resource:
          attributes:
            - key: deployment.environment
              value: "${var.environment}"
              action: upsert
            - key: k8s.cluster.name
              value: "${var.cluster_name}"
              action: upsert
            - key: cloud.provider
              value: "gcp"
              action: upsert
            - key: cloud.platform
              value: "gcp_kubernetes_engine"
              action: upsert
            - key: gcp.project_id
              value: "${var.gcp_project_id}"
              action: upsert

        batch:
          timeout: 1s
          send_batch_size: 256

      exporters:
        # googlecloudtrace: GCP equivalent of awsxray.
        # Converts OTLP spans → Cloud Trace span format.
        # Uses Workload Identity — no service account key file needed.
        # Java agent spans include: db.statement (Cloud SQL), messaging.destination
        # (Pub/Sub), db.cassandra.table (Cassandra) — all visible in Cloud Trace.
        googlecloudtrace:
          project: ${var.gcp_project_id}

        # googlecloud: ships logs AND metrics to Cloud Logging / Cloud Monitoring.
        # Structured JSON log records from the Java app (via OTLP logs) land in
        # Cloud Logging with trace_id as a first-class field — enabling
        # log-to-trace correlation in Cloud Logging UI (click trace_id → Cloud Trace).
        googlecloud:
          project: ${var.gcp_project_id}
          log:
            default_log_name: "opentelemetry.io/${var.project_name}"
          metric:
            instrumentation_library_labels: true
            create_metric_descriptor_buffer_size: 10

        debug:
          verbosity: basic

      service:
        telemetry:
          logs:
            level: warn

        pipelines:
          traces:
            receivers:  [otlp]
            processors: [k8sattributes, resource, batch]
            exporters:  [googlecloudtrace, debug]

          logs:
            receivers:  [otlp]
            processors: [k8sattributes, resource, batch]
            exporters:  [googlecloud]

          metrics:
            receivers:  [otlp]
            processors: [k8sattributes, resource, batch]
            exporters:  [googlecloud]
    YAML
  }

  depends_on = [kubernetes_namespace.monitoring]
}

# ─── DaemonSet ────────────────────────────────────────────────────────────────
# Key difference from AWS: image is otel/opentelemetry-collector-contrib.
# The AWS ADOT image does not include the googlecloudtrace exporter.
# The contrib image includes all community exporters including both AWS and GCP.
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
          "prometheus.io/scrape" = "true"
          "prometheus.io/port"   = "8888"
          "prometheus.io/path"   = "/metrics"
        }
      }

      spec {
        service_account_name            = kubernetes_service_account.otel_collector.metadata[0].name
        automount_service_account_token = true

        # initContainer: downloads the OTEL Java agent JAR and places it at
        # /otel/opentelemetry-javaagent.jar on a shared volume. Spring Boot pods
        # mount this volume and set:
        #   JAVA_TOOL_OPTIONS=-javaagent:/otel/opentelemetry-javaagent.jar
        # This achieves zero-code instrumentation — the Java app is never modified.
        # Auto-instruments: Spring MVC, JDBC (Cloud SQL), Pub/Sub, Cassandra driver.
        init_container {
          name    = "otel-java-agent-installer"
          image   = "busybox:1.36"
          command = ["sh", "-c", <<-CMD
            wget -q -O /otel/opentelemetry-javaagent.jar \
              https://github.com/open-telemetry/opentelemetry-java-instrumentation/releases/download/v2.10.0/opentelemetry-javaagent.jar
          CMD
          ]
          volume_mount {
            name       = "otel-java-agent"
            mount_path = "/otel"
          }
        }

        container {
          name  = "otel-collector"
          # contrib image — required for googlecloudtrace exporter.
          # AWS ADOT image cannot export to GCP.
          image = "otel/opentelemetry-collector-contrib:0.114.0"
          args  = ["--config=/conf/config.yaml"]

          port {
            name           = "otlp-grpc"
            container_port = 4317
            host_port      = 4317
            protocol       = "TCP"
          }
          port {
            name           = "otlp-http"
            container_port = 4318
            host_port      = 4318
            protocol       = "TCP"
          }
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
          volume_mount {
            name       = "otel-java-agent"
            mount_path = "/otel"
          }

          liveness_probe {
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
        # Shared volume between initContainer and collector for the Java agent JAR
        volume {
          name = "otel-java-agent"
          empty_dir {}
        }

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
    }
    port {
      name        = "otlp-http"
      port        = 4318
      target_port = 4318
    }
    port {
      name        = "metrics"
      port        = 8888
      target_port = 8888
    }
  }
}
