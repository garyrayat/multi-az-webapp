# =============================================================================
# RDS MODULE — Managed PostgreSQL with Secrets Manager credentials
# Password never touches tfstate or tfvars — generated here, stored in SM
# Entire module gated behind lab_running to avoid idle DB costs (~$15/month)
# =============================================================================

# -----------------------------------------------------------------------------
# Random password — Terraform generates it, we never see it in plain text
# 32 chars, no special chars that break PostgreSQL connection strings
# -----------------------------------------------------------------------------
resource "random_password" "db" {
  length           = 32
  special          = true
  override_special = "!#$%^&*()-_=+[]"
}

# -----------------------------------------------------------------------------
# Secrets Manager secret — the container that holds the password
# Rotation can be enabled later via Lambda — enterprise standard
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "db" {
  count = var.lab_running ? 1 : 0

  name                    = "${var.project_name}/${var.environment}/db-credentials"
  description             = "RDS PostgreSQL credentials for ${var.project_name} ${var.environment}"
  recovery_window_in_days = 0  # 0 = immediate delete (fine for lab, use 30 in prod)

  tags = {
    Name = "${var.project_name}-${var.environment}-db-secret"
  }
}

# Store the actual credentials as JSON in the secret
# App reads this JSON at runtime: {"username":"...", "password":"...", "host":"..."}
resource "aws_secretsmanager_secret_version" "db" {
  count = var.lab_running ? 1 : 0

  secret_id = aws_secretsmanager_secret.db[0].id
  secret_string = jsonencode({
    username = var.db_username
    password = random_password.db.result
    host     = aws_db_instance.main[0].address
    port     = 5432
    dbname   = var.db_name
  })

  # Wait for DB to exist before storing its endpoint
  depends_on = [aws_db_instance.main]
}

# -----------------------------------------------------------------------------
# RDS PostgreSQL Instance
# lab_running=false  → no instance (saves ~$15/month idle cost)
# lab_running=true   → single-AZ by default
# multi_az=true      → adds standby replica in second AZ (prod pattern)
# -----------------------------------------------------------------------------
resource "aws_db_instance" "main" {
  count = var.lab_running ? 1 : 0

  identifier = "${var.project_name}-${var.environment}-postgres"

  # Engine
  engine               = "postgres"
  engine_version       = "16.3"
  instance_class       = var.db_instance_class

  # Storage — gp3 is cheaper and faster than gp2
  allocated_storage     = 20
  max_allocated_storage = 100   # Auto-scaling storage cap
  storage_type          = "gp3"
  storage_encrypted     = true  # Always encrypt — non-negotiable in enterprise

  # Credentials — pulled from random_password, never hardcoded
  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  # Network — lives in isolated DB subnets, not reachable from internet
  db_subnet_group_name   = var.db_subnet_group_name
  vpc_security_group_ids = [var.db_sg_id]
  publicly_accessible    = false  # Never expose RDS to internet

  # High availability — Multi-AZ only when explicitly enabled
  # Standby replica in second AZ, automatic failover in ~60 seconds
  multi_az = var.multi_az

  # Backups — 7 day retention, non-negotiable for production data
  backup_retention_period = var.lab_running ? 1 : 7
  backup_window           = "03:00-04:00"   # UTC — lowest traffic window
  maintenance_window      = "Mon:04:00-Mon:05:00"

  # Safety — prevent accidental destruction in prod
  # Set to true when you go to production
  deletion_protection = false
  skip_final_snapshot = true  # false in prod — always take final snapshot

  tags = {
    Name = "${var.project_name}-${var.environment}-postgres"
  }
}
