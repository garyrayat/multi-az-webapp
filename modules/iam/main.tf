# Name prefix used across all resources in this module
locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# Create the IAM role that EC2 instances will assume
# Think of this as a job title — defines what the instance is allowed to do
resource "aws_iam_role" "ec2" {
  # Name of the role — visible in AWS IAM console
  name = "${local.name_prefix}-ec2-role"

  # Trust policy — defines WHO can assume this role
  # We are saying: only the EC2 service is allowed to use this role
  assume_role_policy = jsonencode({
    # IAM policy language version — always use this date
    Version = "2012-10-17"
    Statement = [{
      # Allow the action below to happen
      Effect = "Allow"
      # The entity being trusted — in this case the EC2 service itself
      Principal = { Service = "ec2.amazonaws.com" }
      # The action being allowed — sts:AssumeRole means "become this role"
      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name = "${local.name_prefix}-ec2-role"
  }
}

# Attach the SSM policy to the role
# This gives EC2 the ability to be accessed via AWS Systems Manager
# No need to open port 22 or manage SSH keys — enterprise standard
resource "aws_iam_role_policy_attachment" "ssm" {
  # The role we created above
  role = aws_iam_role.ec2.name
  # AWS managed policy — already exists, we just attach it
  # Gives EC2 full SSM access — session manager, run command, patch manager
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attach the CloudWatch policy to the role
# This allows EC2 to send logs and metrics to CloudWatch
# Without this, we have no visibility into what the instance is doing
resource "aws_iam_role_policy_attachment" "cloudwatch" {
  # Same role — we are stacking multiple policies onto one role
  role = aws_iam_role.ec2.name
  # AWS managed policy for CloudWatch agent
  # Allows pushing custom metrics, logs, and performance data
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

# Attach the Secrets Manager policy to the role
# This allows EC2 to read secrets like DB passwords at runtime
# No hardcoded credentials anywhere in code or tfvars — ever
resource "aws_iam_role_policy_attachment" "secrets" {
  # Same role — third policy being stacked onto it
  role = aws_iam_role.ec2.name
  # AWS managed policy for Secrets Manager
  # Allows the instance to fetch and read secrets by name
  policy_arn = "arn:aws:iam::aws:policy/SecretsManagerReadWrite"
}

# Create the instance profile that wraps the IAM role
# EC2 cannot attach a role directly — it needs an instance profile as a container
# Think of the role as the permissions, and the profile as the delivery mechanism
resource "aws_iam_instance_profile" "ec2" {
  # Name of the profile — this is what we reference in the launch template
  name = "${local.name_prefix}-ec2-profile"
  # Attach the role we created above into this profile
  role = aws_iam_role.ec2.name

  tags = {
    Name = "${local.name_prefix}-ec2-profile"
  }
}
