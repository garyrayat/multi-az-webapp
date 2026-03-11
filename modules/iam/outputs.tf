# The instance profile name is what the launch template references
# ASG module needs this to attach the IAM role to every EC2 instance it launches
output "instance_profile_name" {
  description = "EC2 instance profile name"
  value       = aws_iam_instance_profile.ec2.name
}

# The role ARN is useful for debugging and auditing
# Lets you verify in AWS console which role an instance is using
output "ec2_role_arn" {
  description = "EC2 IAM role ARN"
  value       = aws_iam_role.ec2.arn
}
