locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_launch_template" "main" {
  name          = "${local.name_prefix}-lt"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = var.instance_type

  vpc_security_group_ids = [var.app_sg_id]

  iam_instance_profile {
    name = var.instance_profile_name
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    project_name = var.project_name
    environment  = var.environment
  }))

  tags = {
    Name = "${local.name_prefix}-lt"
  }
}

resource "aws_autoscaling_group" "main" {
  name                      = "${local.name_prefix}-asg"
  vpc_zone_identifier       = var.private_subnet_ids
  desired_capacity          = var.lab_running ? 2 : 0
  min_size                  = var.lab_running ? 1 : 0
  max_size                  = var.lab_running ? 4 : 0
  health_check_type         = "ELB"
  health_check_grace_period = 120

  # Only attach target group when lab is running and target_group_arn is not null
  target_group_arns = var.lab_running && var.target_group_arn != null ? [var.target_group_arn] : []

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

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
