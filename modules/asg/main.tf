locals {
  # Reusable name prefix for all resources in this module
  name_prefix = "${var.project_name}-${var.environment}"
}

# ─── Launch Template ────────────────────────────────────
# The blueprint ASG uses to launch every new EC2 instance
# Defines the AMI, instance type, security group, IAM profile
# Every instance ASG creates will look exactly like this template
resource "aws_launch_template" "main" {
  # Name visible in AWS console
  name = "${local.name_prefix}-lt"

  # Amazon Linux 2023 — latest AWS optimised Linux AMI
  # Free tier eligible, pre-installed with SSM agent
  image_id = data.aws_ami.amazon_linux.id

  # t2.micro — free tier eligible, enough for lab workloads
  instance_type = var.instance_type

  # Attach the app security group to every instance launched
  vpc_security_group_ids = [var.app_sg_id]

  # Attach the IAM instance profile — gives access to SSM, CloudWatch, Secrets
  iam_instance_profile {
    name = var.instance_profile_name
  }

  # User data script — runs once when instance first boots
  # Installs nginx and serves a simple page showing the AZ
  # This lets us visually confirm traffic is spreading across AZs
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    project_name = var.project_name
    environment  = var.environment
  }))

  tags = {
    Name = "${local.name_prefix}-lt"
  }
}

# ─── AMI Data Source ────────────────────────────────────
# Dynamically fetches the latest Amazon Linux 2023 AMI ID
# Avoids hardcoding AMI IDs which change per region and expire over time
data "aws_ami" "amazon_linux" {
  # Always get the most recent version
  most_recent = true

  # Only return AMIs owned by Amazon
  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# ─── Auto Scaling Group ─────────────────────────────────
# Manages the fleet of EC2 instances across both private subnets
# Automatically replaces unhealthy instances and scales with demand
resource "aws_autoscaling_group" "main" {
  # Name visible in AWS console
  name = "${local.name_prefix}-asg"

  # Spread instances across both private subnets — one per AZ
  # If AZ-1 goes down, ASG launches replacements in AZ-2 automatically
  vpc_zone_identifier = var.private_subnet_ids

  # 0 instances when lab is off, 2 when running
  desired_capacity = var.lab_running ? 2 : 0
  min_size         = var.lab_running ? 1 : 0
  max_size         = var.lab_running ? 4 : 0

  # Register instances into the ALB target group
  # This is how ALB knows which instances to route traffic to
  target_group_arns = [var.target_group_arn]

  # Use ALB health checks not just EC2 status checks
  # ALB health check is stricter — checks if app is actually responding
  health_check_type         = "ELB"
  health_check_grace_period = 120

  # Reference the launch template we created above
  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  # Tag every instance launched by this ASG
  tag {
    key                 = "Name"
    value               = "${local.name_prefix}-ec2"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
}
