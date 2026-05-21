# =============================================================================
# GKE MODULE — mirrors modules/eks/ for GCP
#
# Why the structure is identical to EKS but the primitives differ:
#   EKS: node IAM role + policy attachments (AWS IAM controls pod permissions)
#   GKE: node SA + Workload Identity (GCP SA annotation controls pod permissions)
#
# Workload Identity replaces node IAM roles for pod-level auth the same way
# IRSA does on EKS — a K8s ServiceAccount is annotated with a GCP service account,
# and GCP issues short-lived tokens to pods that use that K8s SA. No key files,
# no ambient node credentials leaking to all pods on the node.
#
# App stack: Java Spring Boot, Cloud SQL (PostgreSQL), Pub/Sub, Cassandra, GKE
#
# OTEL auth flow (GCP equivalent of node-role policy attachment on EKS):
#   1. google_service_account.otel_collector — GCP SA with trace/log/metric roles
#   2. google_service_account_iam_member (workloadIdentityUser) — links K8s SA
#      "monitoring/otel-collector" to the GCP SA
#   3. otel-gcp module's kubernetes_service_account is annotated with the GCP SA
#      email — GKE Metadata Server exchanges the K8s token for a GCP access token
#   No static credentials anywhere. Same zero-secret posture as IRSA on EKS.
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ─── Node Service Account ─────────────────────────────────────────────────────
# GKE nodes run as this GCP SA. Unlike EKS where the node IAM role also covers
# pod-level access, on GKE the node SA only needs minimum node-level permissions.
# Pod-level access is handled separately via Workload Identity (below).
resource "google_service_account" "node" {
  account_id   = "${local.name_prefix}-gke-node"
  display_name = "${local.name_prefix} GKE Node SA"
  project      = var.gcp_project_id
}

# Minimum permissions for GKE nodes to function:
#   logging.logWriter         — ship node-level logs (kubelet, containerd) to Cloud Logging
#   monitoring.metricWriter   — ship node-level metrics (CPU, memory) to Cloud Monitoring
#   monitoring.viewer         — read metrics for HPA / VPA
#   stackdriver.resourceMetadata.writer — node metadata visible in Cloud Monitoring dashboards
resource "google_project_iam_member" "node_log_writer" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_metric_writer" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_monitoring_viewer" {
  project = var.gcp_project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.node.email}"
}

resource "google_project_iam_member" "node_metadata_writer" {
  project = var.gcp_project_id
  role    = "roles/stackdriver.resourceMetadata.writer"
  member  = "serviceAccount:${google_service_account.node.email}"
}

# ─── GKE Cluster ──────────────────────────────────────────────────────────────
# remove_default_node_pool=true: GKE requires an initial node count to bootstrap
# the cluster, but we immediately replace it with our own managed node pool so we
# control machine type, autoscaling, and Workload Identity config.
resource "google_container_cluster" "main" {
  name     = var.cluster_name
  location = var.gcp_region
  project  = var.gcp_project_id

  # Remove the bootstrap node pool — our managed pool (below) takes over
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.network
  subnetwork = var.subnetwork

  # Workload Identity pool: enables pods to authenticate as GCP SAs.
  # Format: {project_id}.svc.id.goog
  # This is what makes the OTEL collector's zero-secret auth work.
  # Without this, pods would fall back to the node SA (too broad).
  workload_identity_config {
    workload_pool = "${var.gcp_project_id}.svc.id.goog"
  }

  # Private nodes: worker nodes get private IPs only — equivalent to EKS
  # endpoint_private_access=true. The control plane endpoint stays public
  # so Terraform and kubectl (running locally / in CI) can reach it.
  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  # Release channel: REGULAR gets GKE-tested versions ~2-3 weeks after GA.
  # Equivalent to EKS version pinning but managed — GKE auto-upgrades
  # control plane and nodes within the channel.
  release_channel {
    channel = "REGULAR"
  }

  tags = [local.name_prefix, var.environment]
}

# ─── Managed Node Pool ────────────────────────────────────────────────────────
# GCP equivalent of aws_eks_node_group. GKE manages the underlying MIG
# (Managed Instance Group) — same concept as EKS managing an ASG internally.
resource "google_container_node_pool" "main" {
  name     = "${local.name_prefix}-nodes"
  cluster  = google_container_cluster.main.name
  location = var.gcp_region
  project  = var.gcp_project_id

  # Initial count per zone. With autoscaling (below) GKE adjusts this.
  node_count = var.desired_nodes

  node_config {
    machine_type = var.node_machine_type   # e.g., e2-standard-2

    # Node runs as the node SA defined above (not default compute SA)
    service_account = google_service_account.node.email

    # cloud-platform scope — required when using Workload Identity.
    # It sounds broad but Workload Identity tokens are scoped to the GCP SA,
    # so the node SA itself has only the four roles above.
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]

    # GKE_METADATA: nodes serve Workload Identity tokens from the metadata server.
    # Without this, pods fall back to the legacy metadata API and Workload Identity
    # doesn't work — the collector would fail to authenticate to Cloud Trace.
    workload_metadata_config {
      mode = "GKE_METADATA"
    }

    labels = {
      project     = var.project_name
      environment = var.environment
    }
  }

  autoscaling {
    min_node_count = var.min_nodes
    max_node_count = var.max_nodes
  }

  # Node auto-upgrade keeps nodes on the latest GKE patch for the cluster version
  management {
    auto_upgrade = true
    auto_repair  = true
  }

  depends_on = [
    google_project_iam_member.node_log_writer,
    google_project_iam_member.node_metric_writer,
    google_project_iam_member.node_monitoring_viewer,
    google_project_iam_member.node_metadata_writer,
  ]
}

# ─── OTEL Collector — GCP Service Account + Workload Identity ─────────────────
# GCP equivalent of the two aws_iam_role_policy_attachment resources in modules/eks:
#   EKS: node_xray (AWSXRayDaemonWriteAccess) + node_cloudwatch_logs (CloudWatchAgentServerPolicy)
#   GKE: otel GCP SA with cloudtrace.agent + logging.logWriter + monitoring.metricWriter
#        + workloadIdentityUser binding to the K8s SA created by otel-gcp module
#
# The K8s SA "monitoring/otel-collector" is created by otel-gcp/main.tf.
# This IAM binding is what connects it to this GCP SA — the same way a node
# role policy attachment connects an EKS node's instance profile to X-Ray.
resource "google_service_account" "otel_collector" {
  account_id   = "${local.name_prefix}-otel"
  display_name = "${local.name_prefix} OTEL Collector — Cloud Trace + Logging + Monitoring"
  project      = var.gcp_project_id
}

# cloudtrace.agent: write spans to Cloud Trace (equivalent to xray:PutTraceSegments)
resource "google_project_iam_member" "otel_trace_agent" {
  project = var.gcp_project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${google_service_account.otel_collector.email}"
}

# logging.logWriter: write structured logs to Cloud Logging (equivalent to logs:PutLogEvents)
resource "google_project_iam_member" "otel_log_writer" {
  project = var.gcp_project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.otel_collector.email}"
}

# monitoring.metricWriter: write OTLP metrics to Cloud Monitoring
resource "google_project_iam_member" "otel_metric_writer" {
  project = var.gcp_project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.otel_collector.email}"
}

# workloadIdentityUser: the binding that lets the K8s SA act as this GCP SA.
# Subject format: serviceAccount:{project}.svc.id.goog[{namespace}/{k8s_sa_name}]
# namespace=monitoring and k8s_sa_name=otel-collector match what otel-gcp/main.tf creates.
# This is the exact GCP equivalent of attaching AWSXRayDaemonWriteAccess to the EKS node role.
resource "google_service_account_iam_member" "otel_workload_identity" {
  service_account_id = google_service_account.otel_collector.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.gcp_project_id}.svc.id.goog[monitoring/otel-collector]"
}
