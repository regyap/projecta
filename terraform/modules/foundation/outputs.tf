output "vpc_id" { value = aws_vpc.this.id }
output "public_subnet_ids" { value = values(aws_subnet.public)[*].id }
output "private_subnet_ids" { value = values(aws_subnet.private)[*].id }
output "artifact_bucket" { value = aws_s3_bucket.artifacts.id }
output "event_table" { value = aws_dynamodb_table.events.name }
output "deployment_queue_url" { value = aws_sqs_queue.deployment.id }
output "deployment_dlq_url" { value = aws_sqs_queue.deployment_dlq.id }
output "event_bus_name" { value = aws_cloudwatch_event_bus.deployment.name }
output "webhook_url" { value = "${aws_apigatewayv2_api.webhook.api_endpoint}/webhooks/gitlab" }

