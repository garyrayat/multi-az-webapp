# =============================================================================
# SQS MODULE
# Creates a main queue + Dead Letter Queue.
# KEDA watches the main queue's ApproximateNumberOfMessages metric to decide
# how many nginx pod replicas to run (1 replica per 5 messages).
#
# Messages that fail processing max_receive_count times go to the DLQ
# so they can be inspected without being lost.
# =============================================================================

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# ─── Dead Letter Queue ────────────────────────────────────────────────────────
# Receives messages the consumer repeatedly fails to process.
# 14-day retention gives enough time to debug and replay failed messages.
resource "aws_sqs_queue" "dlq" {
  name                      = "${local.name_prefix}-${var.queue_name}-dlq"
  message_retention_seconds = 1209600 # 14 days

  tags = { Name = "${local.name_prefix}-${var.queue_name}-dlq" }
}

# ─── Main Queue ───────────────────────────────────────────────────────────────
resource "aws_sqs_queue" "main" {
  name                       = "${local.name_prefix}-${var.queue_name}"
  message_retention_seconds  = var.message_retention_seconds
  visibility_timeout_seconds = var.visibility_timeout_seconds

  # After max_receive_count failed receives, message moves to the DLQ
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receive_count
  })

  tags = { Name = "${local.name_prefix}-${var.queue_name}" }
}

# ─── Queue Policy ─────────────────────────────────────────────────────────────
# Grants the EKS node role permission to interact with the queue.
# KEDA operator runs on the nodes and uses the node's instance profile
# (identityOwner=operator) to call GetQueueAttributes for scaling decisions.
# The application pods would use the same credentials to send/receive messages.
resource "aws_sqs_queue_policy" "main" {
  queue_url = aws_sqs_queue.main.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEKSNodeRoleAccess"
        Effect = "Allow"
        Principal = {
          AWS = var.node_role_arn
        }
        Action = [
          "sqs:SendMessage",
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:GetQueueAttributes",
          "sqs:GetQueueUrl",
        ]
        Resource = aws_sqs_queue.main.arn
      }
    ]
  })
}
