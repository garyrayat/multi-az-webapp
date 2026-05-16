# =============================================================================
# AWS PROVIDER CONFIGURATION
# The terraform{} block (required_version, required_providers, backend) lives
# in backend.tf — only one terraform{} block is allowed per module.
# default_tags propagates to every resource Terraform manages automatically.
# Activate tags in: AWS Console → Billing → Cost Allocation Tags
# =============================================================================
provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      Owner       = var.owner
      CostCenter  = var.cost_center
      ManagedBy   = "terraform"
    }
  }
}

# ─── Helm Provider ─────────────────────────────────────────────────────────────
# Used by the keda module to install KEDA via Helm chart.
# exec auth: calls `aws eks get-token` at runtime to get a short-lived bearer
# token — avoids storing static credentials in Terraform state.
#
# try() handles the case where module.eks[0] doesn't exist yet (count=0 when
# enable_eks=false, or during Phase 1 apply before keda module is targeted).
# When try() returns "", the provider is configured but inert — no helm
# resources exist so the provider is never actually called.
provider "helm" {
  kubernetes {
    host                   = try(module.eks[0].cluster_endpoint, "")
    cluster_ca_certificate = try(base64decode(module.eks[0].cluster_ca_cert), "")

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = [
        "eks", "get-token",
        "--cluster-name", try(module.eks[0].cluster_name, "placeholder"),
        "--region", var.aws_region,
      ]
    }
  }
}

# ─── Kubernetes Provider ───────────────────────────────────────────────────────
# Used by the keda module to apply K8s Deployment, Service, ConfigMap,
# and KEDA CRD manifests (ScaledObject, TriggerAuthentication).
# Same exec auth pattern as the helm provider above.
provider "kubernetes" {
  host                   = try(module.eks[0].cluster_endpoint, "")
  cluster_ca_certificate = try(base64decode(module.eks[0].cluster_ca_cert), "")

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = [
      "eks", "get-token",
      "--cluster-name", try(module.eks[0].cluster_name, "placeholder"),
      "--region", var.aws_region,
    ]
  }
}
