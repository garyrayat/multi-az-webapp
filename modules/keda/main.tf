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
# Provides a minimal nginx.conf that:
#   /health  → 200 OK (ALB health check target)
#   /        → 200 + project/environment info
resource "kubernetes_config_map" "nginx" {
  metadata {
    name      = "nginx-config"
    namespace = kubernetes_namespace.webapp.metadata[0].name
  }

  data = {
    "nginx.conf" = <<-EOF
      events {}
      http {
        server {
          listen 80;

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
