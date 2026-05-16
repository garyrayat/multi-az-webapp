output "queue_url" {
  description = "URL of the main SQS queue — used in KEDA ScaledObject trigger"
  value       = aws_sqs_queue.main.id
}

output "queue_arn" {
  description = "ARN of the main SQS queue"
  value       = aws_sqs_queue.main.arn
}

output "queue_name" {
  description = "Name of the main SQS queue"
  value       = aws_sqs_queue.main.name
}

output "dlq_url" {
  description = "URL of the dead letter queue"
  value       = aws_sqs_queue.dlq.id
}

output "dlq_arn" {
  description = "ARN of the dead letter queue"
  value       = aws_sqs_queue.dlq.arn
}
