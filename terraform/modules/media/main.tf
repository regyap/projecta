variable "name" { type = string }
variable "aws_region" { type = string }
variable "source_dir" { type = string }
variable "enable_geolocation" {
  type    = bool
  default = false
}
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
resource "aws_s3_bucket" "media" {
  bucket_prefix = "${var.name}-media-"
  force_destroy = false
}
resource "aws_s3_bucket_public_access_block" "media" {
  bucket                  = aws_s3_bucket.media.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
resource "aws_s3_bucket_ownership_controls" "media" {
  bucket = aws_s3_bucket.media.id
  rule { object_ownership = "BucketOwnerEnforced" }
}
resource "aws_s3_bucket_versioning" "media" {
  bucket = aws_s3_bucket.media.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "media" {
  bucket = aws_s3_bucket.media.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}
resource "aws_s3_bucket_policy" "media" {
  bucket = aws_s3_bucket.media.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid = "DenyInsecureTransport", Effect = "Deny", Principal = "*", Action = "s3:*"
      Resource = [aws_s3_bucket.media.arn, "${aws_s3_bucket.media.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
}
resource "aws_s3_bucket_lifecycle_configuration" "media" {
  bucket = aws_s3_bucket.media.id
  depends_on = [aws_s3_bucket_versioning.media]
  rule {
    id = "media-retention-30-days"
    status = "Enabled"
    filter { prefix = "" }
    expiration { days = 30 }
    noncurrent_version_expiration { noncurrent_days = 7 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}
resource "aws_sqs_queue" "dlq" {
  name = "${var.name}-media-dlq"
  sqs_managed_sse_enabled = true
  message_retention_seconds = 1209600
}
resource "aws_sqs_queue" "images" {
  name = "${var.name}-media"
  sqs_managed_sse_enabled = true
  visibility_timeout_seconds = 360
  message_retention_seconds = 345600
  redrive_policy = jsonencode({ deadLetterTargetArn = aws_sqs_queue.dlq.arn, maxReceiveCount = 5 })
}
resource "aws_sqs_queue_redrive_allow_policy" "media" {
  queue_url = aws_sqs_queue.dlq.id
  redrive_allow_policy = jsonencode({ redrivePermission = "byQueue", sourceQueueArns = [aws_sqs_queue.images.arn] })
}
resource "aws_sqs_queue_policy" "images" {
  queue_url = aws_sqs_queue.images.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow", Principal = { Service = "s3.amazonaws.com" }, Action = "sqs:SendMessage"
        Resource = aws_sqs_queue.images.arn
        Condition = {
          ArnEquals = { "aws:SourceArn" = aws_s3_bucket.media.arn }
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
        }
      },
      {
        Effect = "Deny", Principal = "*", Action = "sqs:*", Resource = aws_sqs_queue.images.arn
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })
}
# S3 direct notifications require a standard queue; this is separate from the
# existing deployment FIFO queue. Only input/ triggers work; results/ cannot loop.
resource "aws_s3_bucket_notification" "images" {
  bucket = aws_s3_bucket.media.id
  queue {
    queue_arn = aws_sqs_queue.images.arn
    events = ["s3:ObjectCreated:*"]
    filter_prefix = "input/"
  }
  depends_on = [aws_sqs_queue_policy.images, aws_s3_bucket_versioning.media]
}
resource "aws_cloudwatch_log_group" "worker" {
  name = "/aws/lambda/${var.name}-media-worker"
  retention_in_days = 30
}
resource "aws_iam_role" "worker" {
  name = "${var.name}-media-worker"
  assume_role_policy = jsonencode({ Version = "2012-10-17", Statement = [{ Effect = "Allow", Principal = { Service = "lambda.amazonaws.com" }, Action = "sts:AssumeRole" }] })
}
resource "aws_iam_role_policy" "worker" {
  role = aws_iam_role.worker.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat([
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.worker.arn}:*" },
      { Effect = "Allow", Action = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"], Resource = aws_sqs_queue.images.arn },
      { Effect = "Allow", Action = ["s3:GetObject", "s3:GetObjectVersion"], Resource = "${aws_s3_bucket.media.arn}/input/*" },
      { Effect = "Allow", Action = ["s3:PutObject"], Resource = "${aws_s3_bucket.media.arn}/results/*" },
      # DetectLabels has no resource-level ARN; constrain action and region.
      { Effect = "Allow", Action = ["rekognition:DetectLabels"], Resource = "*", Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } } }
    ], var.enable_geolocation ? [
      { Effect = "Allow", Action = ["geo-places:ReverseGeocode"], Resource = "arn:${data.aws_partition.current.partition}:geo-places:${var.aws_region}::provider/default" }
    ] : [])
  })
}
data "archive_file" "worker" {
  type = "zip"
  source_dir = var.source_dir
  output_path = "${path.module}/media-worker.zip"
  excludes = ["__pycache__", "*.pyc"]
}
resource "aws_lambda_function" "worker" {
  function_name = "${var.name}-media-worker"
  role = aws_iam_role.worker.arn
  handler = "handler.handler"
  runtime = "python3.13"
  filename = data.archive_file.worker.output_path
  source_code_hash = data.archive_file.worker.output_base64sha256
  timeout = 60
  memory_size = 256
  environment {
    variables = {
      MEDIA_BUCKET = aws_s3_bucket.media.id
      ENABLE_GEOLOCATION = tostring(var.enable_geolocation)
    }
  }
  depends_on = [aws_iam_role_policy.worker, aws_cloudwatch_log_group.worker]
}
resource "aws_lambda_event_source_mapping" "images" {
  event_source_arn = aws_sqs_queue.images.arn
  function_name = aws_lambda_function.worker.arn
  batch_size = 1
  function_response_types = ["ReportBatchItemFailures"]
  scaling_config { maximum_concurrency = 2 }
}
resource "aws_cloudwatch_metric_alarm" "dlq" {
  alarm_name = "${var.name}-media-dlq-not-empty"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods = 1
  metric_name = "ApproximateNumberOfMessagesVisible"
  namespace = "AWS/SQS"
  period = 60
  statistic = "Maximum"
  threshold = 0
  treat_missing_data = "notBreaching"
  dimensions = { QueueName = aws_sqs_queue.dlq.name }
  alarm_description = "Media processing failed repeatedly; attach notification actions before operational use."
}
output "configuration" {
  value = {
    bucket = aws_s3_bucket.media.id
    queue_url = aws_sqs_queue.images.id
    dlq_url = aws_sqs_queue.dlq.id
    worker_role_arn = aws_iam_role.worker.arn
  }
}
