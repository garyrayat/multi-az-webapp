locals {
  # Reusable name prefix for all resources in this module
  name_prefix = "${var.project_name}-${var.environment}"
}

# ─── Application Load Balancer ──────────────────────────
# The single entry point for all internet traffic into our app
# internal = false means it faces the public internet
# Spans both public subnets across 2 AZs for high availability
# If one AZ goes down, ALB keeps routing to the healthy AZ automatically
resource "aws_lb" "main" {
  # count = 0 when lab_running=false, saves ~$16/month
  count = var.lab_running ? 1 : 0

  # Name visible in AWS console
  name = "${local.name_prefix}-alb"

  # false = internet facing, true = internal only
  internal = false

  # Application Load Balancer — works at HTTP/HTTPS layer (layer 7)
  load_balancer_type = "application"

  # Attach the ALB SG — controls what traffic is allowed in
  security_groups = [var.alb_sg_id]

  # Place ALB across all public subnets — one per AZ
  subnets = var.public_subnet_ids

  # Protect against accidental deletion in production
  enable_deletion_protection = false

  tags = {
    Name = "${local.name_prefix}-alb"
  }
}

# ─── Target Group ───────────────────────────────────────
# The group of EC2 instances that the ALB routes traffic to
# ALB doesn't talk to instances directly — it talks to a target group
# ASG will register instances into this target group automatically
resource "aws_lb_target_group" "main" {
  # count matches ALB — no point having a target group without an ALB
  count = var.lab_running ? 1 : 0

  # Name visible in AWS console
  name = "${local.name_prefix}-tg"

  # Port the EC2 instances are listening on
  port = 80

  # Protocol used between ALB and EC2 instances
  protocol = "HTTP"

  # Target group must be in the same VPC as the instances
  vpc_id = var.vpc_id

  # ─── Health Check ─────────────────────────────────────
  # ALB pings this path on every instance every 30 seconds
  # If an instance fails health checks, ALB stops sending it traffic
  # This is how unhealthy instances are automatically removed
  health_check {
    # Path ALB will hit to check if the instance is healthy
    path = "/health"

    # Healthy threshold — how many consecutive passes = healthy
    healthy_threshold = 2

    # Unhealthy threshold — how many consecutive fails = unhealthy
    unhealthy_threshold = 3

    # How long to wait for a response before marking as failed
    timeout = 5

    # How often to run the health check in seconds
    interval = 30

    # HTTP response code that means the instance is healthy
    matcher = "200"
  }

  tags = {
    Name = "${local.name_prefix}-tg"
  }
}

# ─── Listener ───────────────────────────────────────────
# The listener watches for incoming traffic on a specific port
# When traffic hits port 80, it forwards it to the target group
# Think of it as the rule that connects the ALB to the target group
resource "aws_lb_listener" "http" {
  # count matches ALB and target group
  count = var.lab_running ? 1 : 0

  # Reference the ALB we created above
  # [0] because count makes it a list, we want the first (only) item
  load_balancer_arn = aws_lb.main[0].arn

  # Listen on port 80 for incoming HTTP traffic
  port = 80

  # Protocol to listen on
  protocol = "HTTP"

  # What to do with traffic that matches this listener
  default_action {
    # Forward the traffic to our target group
    type             = "forward"
    target_group_arn = aws_lb_target_group.main[0].arn
  }
}
