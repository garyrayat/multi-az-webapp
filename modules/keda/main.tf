# =============================================================================
# KEDA MODULE
# 1. Installs KEDA via Helm into the keda namespace
# 2. Deploys the nginx app as a Kubernetes Deployment + NodePort Service
# 3. Creates a KEDA ScaledObject that scales nginx based on SQS queue depth
#
# PROVIDER NOTE: The helm and kubernetes providers in provider.tf must already
# be configured with the EKS cluster endpoint. This is guaranteed because
# main.tf declares depends_on = [module.eks] on this module, which ensures
# the cluster exists before any resource in this module is planned.
# =============================================================================

# ─── Namespaces ───────────────────────────────────────────────────────────────
resource "kubernetes_namespace" "keda" {
  metadata {
    name = "keda"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_namespace" "webapp" {
  metadata {
    name = var.app_namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = var.project_name
    }
  }
}

# ─── KEDA Helm Release ────────────────────────────────────────────────────────
# Installs three components:
#   - keda-operator: watches ScaledObjects, creates/updates HPAs
#   - keda-metrics-apiserver: exposes external metrics to the HPA controller
#   - keda-admission-webhooks: validates ScaledObject CRDs on admission
resource "helm_release" "keda" {
  name       = "keda"
  repository = "https://kedacore.github.io/charts"
  chart      = "keda"
  version    = "~2.16"
  namespace  = kubernetes_namespace.keda.metadata[0].name

  # Block until all KEDA pods are Running. This prevents the ScaledObject
  # kubernetes_manifest resources from racing with CRD installation.
  wait    = true
  timeout = 300

  set {
    name  = "operator.replicaCount"
    value = "1"
  }

  depends_on = [kubernetes_namespace.keda]
}

# ─── nginx ConfigMap ─────────────────────────────────────────────────────────
# Two additions over the minimal config:
#
# 1. W3C Trace Context propagation (traceparent)
#    The `map` block reads the incoming `traceparent` header.
#    If present (upstream service already started the trace), it is forwarded as-is.
#    If absent (this is the trace origin), nginx synthesises one from $request_id:
#      format: 00-{32-hex trace-id}-{16-hex parent-id}-01
#    $request_id is nginx's built-in 32-char hex unique request identifier —
#    repurposed as the trace-id. The parent-id is the first 16 chars (padded here
#    to a static value for simplicity; real W3C requires 16 unique hex chars).
#    The synthesised traceparent is echoed back in the response header so clients
#    and downstream callers can attach their own spans to the same trace.
#
# 2. Structured JSON access log (log_format json_combined)
#    Every request emits one JSON line to stdout (picked up by CloudWatch Logs Agent
#    and the OTEL collector's awscloudwatchlogs exporter).
#    Fields: time, method, uri, status, request_id, traceparent — the last two are
#    the correlation IDs that link this log line to an X-Ray trace span.
#    CloudWatch Insights can then query: `filter traceparent like "00-abc123"` to
#    pull every nginx log for a specific distributed trace.
resource "kubernetes_config_map" "nginx" {
  metadata {
    name      = "nginx-config"
    namespace = kubernetes_namespace.webapp.metadata[0].name
    labels = {
      "app.kubernetes.io/part-of" = "observability"
    }
  }

  data = {
    "nginx.conf" = <<-EOF
      events {}

      http {
        # ── Trace Context ──────────────────────────────────────────────────────
        # If the client sent a W3C traceparent header, forward it unchanged.
        # If not, synthesise one: 00-<32-hex>-<16-hex>-01
        # $request_id is nginx's built-in opaque 32-char hex ID — valid trace-id.
        # "0000000000000001" is a placeholder parent-id (first span in the trace).
        # Flags byte "01" = sampled (tell downstream collectors to record this span).
        map $http_traceparent $traceparent_value {
          ""      "00-$request_id-0000000000000001-01";
          default $http_traceparent;
        }

        # ── Structured JSON log format ─────────────────────────────────────────
        # escape=json safely escapes URI, user-agent, and any free-text fields.
        # request_id and traceparent are the two correlation IDs:
        #   - request_id: unique to this nginx request (local correlation)
        #   - traceparent: links to the distributed trace in X-Ray / Cloud Trace
        # service and environment are stamped so CloudWatch Insights queries can
        # filter by project without parsing the log group name.
        log_format json_combined escape=json
          '{'
            '"time":"$time_iso8601",'
            '"method":"$request_method",'
            '"uri":"$request_uri",'
            '"status":$status,'
            '"bytes_sent":$bytes_sent,'
            '"request_time":$request_time,'
            '"request_id":"$request_id",'
            '"traceparent":"$traceparent_value",'
            '"user_agent":"$http_user_agent",'
            '"remote_addr":"$remote_addr",'
            '"service":"${var.project_name}",'
            '"environment":"${var.environment}"'
          '}';

        # Route all access logs through the structured format.
        # /health logs are included — ALB probes show up as status=200 lines,
        # which lets you verify probe frequency and spot health check anomalies.
        access_log /var/log/nginx/access.log json_combined;

        server {
          listen 80;

          # Echo traceparent back so downstream callers can attach child spans.
          # X-Request-ID gives clients a handle to correlate their own logs.
          add_header Traceparent  $traceparent_value always;
          add_header X-Request-ID $request_id        always;

          location /health {
            return 200 'OK';
            add_header Content-Type text/plain;
          }

          location / {
            return 200 'Hello from ${var.project_name} (${var.environment}) - powered by KEDA on EKS';
            add_header Content-Type text/plain;
          }
        }
      }
    EOF
  }

  depends_on = [kubernetes_namespace.webapp]
}

# ─── nginx Deployment ─────────────────────────────────────────────────────────
# KEDA will override the replicas count by creating an HPA targeting this
# Deployment. The initial value of 1 acts as the floor before KEDA takes over.
resource "kubernetes_deployment" "nginx" {
  metadata {
    name      = "nginx"
    namespace = kubernetes_namespace.webapp.metadata[0].name
    labels = {
      app                            = "nginx"
      "app.kubernetes.io/part-of"    = var.project_name
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "nginx"
      }
    }

    template {
      metadata {
        labels = {
          app = "nginx"
        }
      }

      spec {
        container {
          name  = "nginx"
          image = "nginx:alpine"

          port {
            container_port = 80
            protocol       = "TCP"
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }

          volume_mount {
            name       = "nginx-config"
            mount_path = "/etc/nginx/nginx.conf"
            sub_path   = "nginx.conf"
          }

          # ALB starts routing traffic only after this probe passes
          readiness_probe {
            http_get {
              path = "/health"
              port = 80
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            failure_threshold     = 3
          }

          # Pod is restarted if this probe fails
          liveness_probe {
            http_get {
              path = "/health"
              port = 80
            }
            initial_delay_seconds = 10
            period_seconds        = 30
            failure_threshold     = 3
          }
        }

        volume {
          name = "nginx-config"
          config_map {
            name = kubernetes_config_map.nginx.metadata[0].name
          }
        }
      }
    }
  }

  depends_on = [kubernetes_namespace.webapp]
}

# ─── NodePort Service ─────────────────────────────────────────────────────────
# Exposes nginx pods on every worker node at port 30080.
# The ALB target group (configured with target_port=30080) health-checks and
# routes traffic directly to nodes on this port. kube-proxy forwards it to pods.
resource "kubernetes_service" "nginx" {
  metadata {
    name      = "nginx"
    namespace = kubernetes_namespace.webapp.metadata[0].name
  }

  spec {
    selector = {
      app = "nginx"
    }

    type = "NodePort"

    port {
      port        = 80
      target_port = 80
      node_port   = 30080
      protocol    = "TCP"
    }
  }

  depends_on = [kubernetes_namespace.webapp]
}

# ─── KEDA TriggerAuthentication ───────────────────────────────────────────────
# identityOwner=operator: the KEDA operator pod uses the node's AWS instance
# profile credentials to call SQS:GetQueueAttributes for scaling decisions.
# No IRSA, no secrets — the node role's AmazonSQSReadOnlyAccess policy covers this.
resource "kubernetes_manifest" "keda_trigger_auth" {
  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "TriggerAuthentication"
    metadata = {
      name      = "keda-aws-credentials"
      namespace = var.app_namespace
    }
    spec = {
      podIdentity = {
        provider      = "aws"
        identityOwner = "keda"
      }
    }
  }

  # CRDs must exist (installed by Helm) before this manifest can be applied
  depends_on = [helm_release.keda, kubernetes_namespace.webapp]
}

# ─── KEDA ScaledObject ────────────────────────────────────────────────────────
# Tells KEDA to scale the nginx Deployment based on SQS queue depth.
# Formula: target replicas = ceil(queue_depth / queueLength)
#   0-4 msgs  → 1 pod (minReplicaCount floor)
#   5-9 msgs  → 1 pod (⌈5/5⌉ = 1)
#   10-14     → 2 pods
#   20        → 4 pods
#   50        → 10 pods (maxReplicaCount ceiling)
#
# cooldownPeriod=300: KEDA waits 5 min after queue empties before scaling in,
# avoiding thrashing if the queue briefly dips to zero.
resource "kubernetes_manifest" "keda_scaled_object" {
  manifest = {
    apiVersion = "keda.sh/v1alpha1"
    kind       = "ScaledObject"
    metadata = {
      name      = "nginx-scaledobject"
      namespace = var.app_namespace
    }
    spec = {
      scaleTargetRef = {
        name = kubernetes_deployment.nginx.metadata[0].name
      }
      minReplicaCount = 1
      maxReplicaCount = 10
      cooldownPeriod  = 300

      triggers = [{
        type = "aws-sqs-queue"
        authenticationRef = {
          name = kubernetes_manifest.keda_trigger_auth.manifest.metadata.name
        }
        metadata = {
          queueURL      = var.queue_url
          queueLength   = "5"
          awsRegion     = var.aws_region
          identityOwner = "keda"
        }
      }]
    }
  }

  depends_on = [
    helm_release.keda,
    kubernetes_deployment.nginx,
    kubernetes_manifest.keda_trigger_auth,
  ]
}
