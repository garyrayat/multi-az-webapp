output "cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint — used by helm and kubernetes providers"
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_cert" {
  description = "Base64-encoded cluster CA certificate — used by helm and kubernetes providers"
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "node_group_asg_name" {
  description = "Name of the Auto Scaling Group backing the EKS node group"
  value       = aws_eks_node_group.main.resources[0].autoscaling_groups[0].name
}

output "node_role_arn" {
  description = "ARN of the EKS node IAM role — passed to SQS module for queue policy"
  value       = aws_iam_role.node.arn
}
