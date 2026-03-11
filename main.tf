# =============================================================================
# ROOT MODULE — Wires all modules together
# Think of this as the orchestration layer. Each module is a component.
# =============================================================================

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
}

# --- Auto Scaling Group — only when lab_running=true (EC2 costs) ---
module "asg" {
  source = "./modules/asg"

  private_subnet_ids    = module.vpc.private_subnet_ids
  app_sg_id             = module.security_groups.app_sg_id
  instance_profile_name = module.iam.instance_profile_name
  instance_type         = var.instance_type
  project_name          = var.project_name
  environment           = var.environment
  lab_running           = var.lab_running

  # coalesce() handles null safely: if ALB isn't deployed, pass "" instead of null
  target_group_arn = var.lab_running ? coalesce(module.alb.target_group_arn, "") : ""
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
