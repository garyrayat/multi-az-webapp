# =============================================================================
# VPC ENDPOINTS MODULE — Reduces NAT Gateway data transfer costs
# Gateway endpoints (S3): FREE — always deployed
# Interface endpoints (SSM, CW, Secrets): $0.01/hr/AZ — lab_running gated
# =============================================================================

# -----------------------------------------------------------------------------
# Security Group for Interface Endpoints
# Interface endpoints expose ENIs in your private subnets.
# EC2 instances connect to them over HTTPS (443). Only allow VPC CIDR inbound.
# -----------------------------------------------------------------------------
resource "aws_security_group" "vpc_endpoints" {
  name        = "${var.project_name}-${var.environment}-vpc-endpoints-sg"
  description = "Allow HTTPS from within VPC to interface endpoints"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS from VPC CIDR to interface endpoints"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-vpc-endpoints-sg"
  }
}

# -----------------------------------------------------------------------------
# S3 Gateway Endpoint — FREE, no hourly charge
# Gateway endpoints work via route table entries, not ENIs.
# We attach it to every private route table so all app tier traffic to S3
# bypasses the NAT gateway entirely.
# -----------------------------------------------------------------------------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.private_route_table_ids

  tags = {
    Name = "${var.project_name}-${var.environment}-s3-gateway-endpoint"
  }
}

# -----------------------------------------------------------------------------
# Interface Endpoints — $0.01/hr per AZ per endpoint
# Each creates an ENI in each private subnet. Traffic to AWS services
# (SSM, CloudWatch, Secrets Manager) goes through VPC private network
# instead of NAT Gateway → eliminates NAT data processing charges.
# Only deployed when lab_running=true to control lab costs.
# -----------------------------------------------------------------------------
locals {
  # Map of interface endpoints to create
  # key = short name, value = full AWS service name
  interface_endpoints = {
    ssm = {
      service_name = "com.amazonaws.${var.aws_region}.ssm"
    }
    ec2messages = {
      service_name = "com.amazonaws.${var.aws_region}.ec2messages"
    }
    ssmmessages = {
      service_name = "com.amazonaws.${var.aws_region}.ssmmessages"
    }
    logs = {
      service_name = "com.amazonaws.${var.aws_region}.logs"
    }
    secretsmanager = {
      service_name = "com.amazonaws.${var.aws_region}.secretsmanager"
    }
  }
}

resource "aws_vpc_endpoint" "interface" {
  # Only create when lab is running — interface endpoints cost $0.01/hr/AZ
  # 5 endpoints × 2 AZs × $0.01 × 730hrs = ~$73/month at full run
  for_each = var.lab_running ? local.interface_endpoints : {}

  vpc_id              = var.vpc_id
  service_name        = each.value.service_name
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.private_subnet_ids
  security_group_ids  = [aws_security_group.vpc_endpoints.id]
  private_dns_enabled = true  # Overrides default DNS → transparently redirects API calls

  tags = {
    Name = "${var.project_name}-${var.environment}-${each.key}-endpoint"
  }
}
