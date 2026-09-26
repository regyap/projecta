# Explicit controls, independent from account-level defaults.
resource "aws_s3_bucket_ownership_controls" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule { object_ownership = "BucketOwnerEnforced" }
}

data "aws_iam_policy_document" "artifacts_transport" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.artifacts.arn, "${aws_s3_bucket.artifacts.arn}/*"]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}
resource "aws_s3_bucket_policy" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  policy = data.aws_iam_policy_document.artifacts_transport.json
}
resource "aws_s3_bucket_lifecycle_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter { prefix = "" }
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }
}
resource "aws_cloudwatch_log_group" "webhook" {
  name              = "/aws/lambda/${local.name}-webhook"
  retention_in_days = 30
  tags              = local.tags
}
resource "aws_sqs_queue_redrive_allow_policy" "deployment" {
  queue_url = aws_sqs_queue.deployment_dlq.id
  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns    = [aws_sqs_queue.deployment.arn]
  })
}
resource "aws_cloudwatch_metric_alarm" "deployment_dlq" {
  alarm_name          = "${local.name}-deployment-dlq-not-empty"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "ApproximateNumberOfMessagesVisible"
  namespace           = "AWS/SQS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  dimensions          = { QueueName = aws_sqs_queue.deployment_dlq.name }
  alarm_description   = "Consumer failures reached the deployment DLQ. Attach notification actions before operational use."
  tags                = local.tags
}

# EventBridge delivery failures are distinct from failures after SQS consumption.
resource "aws_sqs_queue" "event_delivery_dlq" {
  name = "${local.name}-event-delivery-dlq"
  sqs_managed_sse_enabled = true
  message_retention_seconds = 1209600
}
resource "aws_sqs_queue_policy" "event_delivery_dlq" {
  queue_url = aws_sqs_queue.event_delivery_dlq.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = { Service = "events.amazonaws.com" }
      Action = "sqs:SendMessage"
      Resource = aws_sqs_queue.event_delivery_dlq.arn
      Condition = {
        ArnEquals = { "aws:SourceArn" = aws_cloudwatch_event_rule.deployment_requested.arn }
        StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
      }
    }]
  })
}
resource "aws_cloudwatch_metric_alarm" "event_delivery_dlq" {
  alarm_name = "${local.name}-event-delivery-dlq-not-empty"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = 1
  metric_name = "ApproximateNumberOfMessagesVisible"
  namespace = "AWS/SQS"
  period = 60
  statistic = "Maximum"
  threshold = 0
  treat_missing_data = "notBreaching"
  dimensions = { QueueName = aws_sqs_queue.event_delivery_dlq.name }
}
