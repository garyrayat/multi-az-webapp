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
