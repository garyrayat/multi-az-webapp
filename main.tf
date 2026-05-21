# =============================================================================
# ROOT MODULE — Wires all modules together
# Think of this as the orchestration layer. Each module is a component.
# =============================================================================

locals {
  # true only when BOTH lab_running and enable_eks are set.
  # Guards all EKS/SQS/KEDA resource creation so they never run in skeleton mode.
  use_eks = var.lab_running && var.enable_eks

  # GKE path: gated on enable_gke + a non-empty gcp_project_id.
  # Independent of lab_running — GCP billing is separate from AWS.
  use_gke = var.enable_gke && var.gcp_project_id != ""
}

# --- Networking foundation — always deployed (free tier resources) ---
module "vpc" {
  source = "./modules/vpc"

  project_name          = var.project_name
  environment           = var.environment
  vpc_cidr              = var.vpc_cidr
  availability_zones    = var.availability_zones
  public_subnet_cidrs   = var.public_subnet_cidrs
  private_subnet_cidrs  = var.private_subnet_cidrs
  database_subnet_cidrs = var.database_subnet_cidrs
  lab_running           = var.lab_running
}

# --- Security groups — always deployed (free) ---
module "security_groups" {
  source = "./modules/security_groups"

  vpc_id       = module.vpc.vpc_id
  project_name = var.project_name
  environment  = var.environment
}

# --- IAM roles — always deployed (free) ---
module "iam" {
  source = "./modules/iam"

  project_name = var.project_name
  environment  = var.environment
}

# --- Load Balancer — only when lab_running=true ($0.008/hr) ---
module "alb" {
  source = "./modules/alb"

  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
  alb_sg_id         = module.security_groups.alb_sg_id
  project_name      = var.project_name
  environment       = var.environment
  lab_running       = var.lab_running

  # NodePort 30080 when EKS path is active; port 80 for the legacy EC2 path
  target_port = local.use_eks ? 30080 : 80
}

# --- Auto Scaling Group — disabled when EKS is active ---
# When enable_eks=true, pass lab_running=false so the ASG desired/min/max
# all resolve to 0 (no EC2 instances launched). The launch template still
# gets created but nothing runs, keeping the EC2 path intact for easy rollback.
module "asg" {
  source = "./modules/asg"

  private_subnet_ids    = module.vpc.private_subnet_ids
  app_sg_id             = module.security_groups.app_sg_id
  instance_profile_name = module.iam.instance_profile_name
  instance_type         = var.instance_type
  project_name          = var.project_name
  environment           = var.environment

  # Disable ASG when EKS takes over
  lab_running = var.lab_running && !var.enable_eks

  # coalesce() handles null safely: if ALB isn't deployed, pass "" instead of null
  target_group_arn = (var.lab_running && !var.enable_eks) ? coalesce(module.alb.target_group_arn, "") : ""
}

# ✅ NEW — VPC Endpoints — reduces NAT data transfer costs
# S3 gateway endpoint is always on (FREE).
# Interface endpoints (SSM, CW, Secrets) only when lab_running=true.
module "vpc_endpoints" {
  source = "./modules/vpc_endpoints"

  vpc_id                  = module.vpc.vpc_id
  vpc_cidr                = var.vpc_cidr
  private_subnet_ids      = module.vpc.private_subnet_ids
  private_route_table_ids = module.vpc.private_route_table_ids
  aws_region              = var.aws_region
  project_name            = var.project_name
  environment             = var.environment
  lab_running             = var.lab_running
}

# ✅ NEW — AWS Budget — cost guardrail with SNS email alerts
# Always deployed. Budget itself is free; SNS costs fractions of a penny.
module "budget" {
  source = "./modules/budget"

  project_name       = var.project_name
  environment        = var.environment
  budget_limit       = var.budget_limit
  warning_threshold  = 50
  critical_threshold = 80
  alert_emails       = var.alert_emails
}

# --- RDS PostgreSQL — only when lab_running=true (~$15/month) ---
module "rds" {
  source = "./modules/rds"

  project_name         = var.project_name
  environment          = var.environment
  lab_running          = var.lab_running
  db_subnet_group_name = module.vpc.db_subnet_group_name
  db_sg_id             = module.security_groups.db_sg_id
  db_instance_class    = var.db_instance_class
  db_name              = var.db_name
  db_username          = var.db_username
  multi_az             = var.multi_az
}

# --- CloudWatch — observability layer (log groups always on, alarms/dashboard when lab running) ---
module "cloudwatch" {
  source = "./modules/cloudwatch"

  project_name            = var.project_name
  environment             = var.environment
  aws_region              = var.aws_region
  lab_running             = var.lab_running
  alert_emails            = var.alert_emails
  asg_name                = module.asg.asg_name
  alb_arn_suffix          = module.alb.alb_arn_suffix != null ? module.alb.alb_arn_suffix : ""
  target_group_arn_suffix = module.alb.target_group_arn_suffix != null ? module.alb.target_group_arn_suffix : ""
  db_instance_id          = var.lab_running && module.rds.db_address != null ? module.rds.db_address : ""
}

# =============================================================================
# EKS — replaces EC2/ASG when lab_running=true AND enable_eks=true
# =============================================================================

module "eks" {
  source = "./modules/eks"

  count = local.use_eks ? 1 : 0

  cluster_name       = "${var.project_name}-${var.environment}-eks"
  kubernetes_version = var.kubernetes_version
  node_instance_type = var.eks_node_instance_type
  desired_nodes      = var.eks_desired_nodes
  min_nodes          = 1
  max_nodes          = 4

  private_subnet_ids = module.vpc.private_subnet_ids
  app_sg_id          = module.security_groups.app_sg_id

  # The EKS node group ASG is attached to this target group
  # so ALB routes traffic to nodes on NodePort 30080
  target_group_arn = coalesce(module.alb.target_group_arn, "")

  project_name = var.project_name
  environment  = var.environment
}

# =============================================================================
# SQS — event source for KEDA; conditional on use_eks
# =============================================================================

module "sqs" {
  source = "./modules/sqs"

  count = local.use_eks ? 1 : 0

  queue_name    = "webapp-events"
  node_role_arn = module.eks[0].node_role_arn
  project_name  = var.project_name
  environment   = var.environment
}

# =============================================================================
# KEDA — Helm install + K8s manifests; conditional on use_eks
#
# IMPORTANT: depends_on is critical here. The helm and kubernetes providers
# in provider.tf need the EKS cluster to be reachable before Terraform plans
# any helm_release or kubernetes_* resources. Without this, a fresh apply
# will fail because the API server doesn't exist yet.
#
# Use two-phase apply:
#   Phase 1: terraform apply -target=module.eks -target=module.sqs ... (all except keda)
#   Phase 2: terraform apply (full apply, EKS exists, providers can authenticate)
# =============================================================================

module "keda" {
  source = "./modules/keda"

  count = local.use_eks ? 1 : 0

  cluster_name  = module.eks[0].cluster_name
  queue_url     = module.sqs[0].queue_url
  queue_name    = module.sqs[0].queue_name
  aws_region    = var.aws_region
  app_namespace = "webapp"
  project_name  = var.project_name
  environment   = var.environment

  depends_on = [module.eks, module.sqs]
}

# =============================================================================
# OTEL — Collector DaemonSet on EKS
# Gated on use_eks: there are no nodes to schedule on unless EKS is running.
#
# What this deploys:
#   - Namespace: monitoring
#   - ServiceAccount + ClusterRole + ClusterRoleBinding (k8sattributes needs
#     GET/LIST/WATCH on pods, namespaces, nodes to enrich spans with k8s metadata)
#   - ConfigMap: collector pipeline config (otlp → k8sattributes+resource+batch
#     → awsxray + awscloudwatchlogs)
#   - DaemonSet: one ADOT collector pod per node, hostPort 4317/4318
#   - ClusterIP Service: DNS fallback for pods that don't use localhost
#
# Auth: node IAM instance profile — the two policy attachments added to
# module.eks (AWSXRayDaemonWriteAccess + CloudWatchAgentServerPolicy) are
# what allow the collector to export without any static credentials.
#
# Trace path: nginx/Lambda → OTLP localhost:4317 → ADOT collector → X-Ray
# Log path:   nginx/Lambda → OTLP localhost:4317 → ADOT collector → CloudWatch
# =============================================================================

module "otel" {
  source = "./modules/otel-aws"

  count = local.use_eks ? 1 : 0

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
  cluster_name = module.eks[0].cluster_name

  # Must run after EKS cluster and KEDA so the k8s API server is reachable
  # and the monitoring namespace doesn't conflict with any helm-managed resources.
  depends_on = [module.eks, module.keda]
}

# =============================================================================
# GKE — GCP equivalent of modules/eks
# Deploys: GKE cluster, managed node pool, node SA, OTEL collector GCP SA,
# Workload Identity IAM binding (mirrors EKS node role policy attachments).
#
# Requires the google provider configured in provider.tf with gcp_project_id
# and gcp_region. Gated on enable_gke=true + gcp_project_id non-empty.
# =============================================================================

module "gke" {
  source = "./modules/gke"

  count = local.use_gke ? 1 : 0

  cluster_name      = "${var.project_name}-${var.environment}-gke"
  gcp_project_id    = var.gcp_project_id
  gcp_region        = var.gcp_region
  node_machine_type = var.gke_node_machine_type
  desired_nodes     = var.gke_desired_nodes
  min_nodes         = 1
  max_nodes         = 4

  project_name = var.project_name
  environment  = var.environment
}

# =============================================================================
# OTEL-GCP — Collector DaemonSet on GKE
# Mirrors modules/otel-aws exactly — same pipeline, GCP exporters + auth.
#
# What changes vs otel-aws:
#   Image:      otel/opentelemetry-collector-contrib (not ADOT — no Google exporters in ADOT)
#   Exporters:  googlecloudtrace + googlecloud  (vs awsxray + awscloudwatchlogs)
#   Auth:       Workload Identity annotation on K8s SA (vs node instance profile)
#   Extra:      initContainer downloads OTEL Java agent for Spring Boot zero-code instrumentation
#
# gcp_service_account_email comes from module.gke[0].otel_service_account_email —
# this is the GCP SA that has cloudtrace.agent + logging.logWriter + monitoring.metricWriter
# and is bound to the K8s SA "monitoring/otel-collector" via Workload Identity.
# =============================================================================

module "otel_gcp" {
  source = "./modules/otel-gcp"

  count = local.use_gke ? 1 : 0

  project_name              = var.project_name
  environment               = var.environment
  gcp_project_id            = var.gcp_project_id
  cluster_name              = module.gke[0].cluster_name
  # The GCP SA email output from modules/gke — passed here to annotate the K8s SA.
  # This is the single wire that connects Workload Identity: GKE sees the annotation,
  # maps K8s token → GCP SA token, collector exports without any static credentials.
  gcp_service_account_email = module.gke[0].otel_service_account_email

  depends_on = [module.gke]
}

# =============================================================================
# PROMETHEUS — kube-prometheus-stack (Prometheus + Grafana)
# Gated on use_eks — needs a running cluster to schedule pods.
#
# Access after apply (no LoadBalancer, no cost):
#   Grafana:    kubectl port-forward -n monitoring svc/prometheus-grafana 3000:80
#   Prometheus: kubectl port-forward -n monitoring svc/prometheus-kube-prometheus-prometheus 9090:9090
#
# Depends on module.otel because:
#   1. otel-aws creates the monitoring namespace — prometheus uses a data source
#      to reference it rather than recreating it (avoids ownership conflict)
#   2. PodMonitor targets the otel-collector DaemonSet pods (port 8888) —
#      the pods must exist before the monitor is useful
# =============================================================================

module "prometheus" {
  source = "./modules/prometheus"

  count = local.use_eks ? 1 : 0

  project_name           = var.project_name
  environment            = var.environment
  grafana_admin_password = var.grafana_admin_password

  depends_on = [module.eks, module.keda, module.otel]
}

# =============================================================================
# LAMBDA — simple web app with function URL (satisfies AWS $20 credit activity)
# Deployed independently of lab_running/enable_eks — always on when enabled.
# =============================================================================

module "lambda" {
  source = "./modules/lambda"

  count = var.enable_lambda ? 1 : 0

  project_name = var.project_name
  environment  = var.environment
  aws_region   = var.aws_region
}
