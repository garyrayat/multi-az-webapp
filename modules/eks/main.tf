# =============================================================================
# EKS MODULE
# Creates an EKS cluster + managed node group to replace the EC2/ASG web tier.
# KEDA runs on this cluster and scales nginx pods based on SQS queue depth.
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ─── Cluster IAM Role ─────────────────────────────────────────────────────────
# The EKS control plane assumes this role to manage AWS resources on our behalf
# (e.g., creating/updating ENIs, load balancer integrations, CloudWatch logs).
resource "aws_iam_role" "cluster" {
  name = "${local.name_prefix}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${local.name_prefix}-eks-cluster-role" }
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ─── Node IAM Role ─────────────────────────────────────────────────────────────
# Worker node EC2 instances assume this role.
# The 4 managed policies cover: K8s API auth, VPC CNI networking, ECR image pulls,
# and SQS read access for KEDA's ambient credential authentication.
resource "aws_iam_role" "node" {
  name = "${local.name_prefix}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = { Name = "${local.name_prefix}-eks-node-role" }
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_cni" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# KEDA uses identityOwner=operator: the operator pod inherits the node's instance
# profile, so the node role needs permission to call SQS:GetQueueAttributes.
resource "aws_iam_role_policy_attachment" "node_sqs" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSReadOnlyAccess"
}

# ─── EKS Cluster ──────────────────────────────────────────────────────────────
resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.kubernetes_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids = var.private_subnet_ids
    # Pass the app security group so the cluster's ENIs join the same SG.
    # This lets the ALB reach the nodes on NodePort 30080.
    security_group_ids = [var.app_sg_id]

    # public access required so Terraform (running locally/CI) can reach the API server
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  # Cluster role must have the policy attached before EKS can call AWS APIs
  depends_on = [aws_iam_role_policy_attachment.cluster_policy]

  tags = { Name = var.cluster_name }
}

# ─── EKS Managed Node Group ───────────────────────────────────────────────────
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.name_prefix}-nodes"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = var.private_subnet_ids
  instance_types  = [var.node_instance_type]

  # EKS-optimized Amazon Linux 2 AMI — AWS picks the right version for the K8s release
  ami_type = "AL2_x86_64"

  scaling_config {
    desired_size = var.desired_nodes
    min_size     = var.min_nodes
    max_size     = var.max_nodes
  }

  # All 4 node role policy attachments must complete before nodes attempt to join
  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_cni,
    aws_iam_role_policy_attachment.node_ecr,
    aws_iam_role_policy_attachment.node_sqs,
  ]

  tags = { Name = "${local.name_prefix}-node-group" }
}

# ─── ALB Target Group Attachment ──────────────────────────────────────────────
# The managed node group manages an Auto Scaling Group internally.
# This attachment registers that ASG with the ALB target group so the ALB
# can health-check and route traffic to nodes on NodePort 30080.
resource "aws_autoscaling_attachment" "eks_to_alb" {
  autoscaling_group_name = aws_eks_node_group.main.resources[0].autoscaling_groups[0].name
  lb_target_group_arn    = var.target_group_arn
}
