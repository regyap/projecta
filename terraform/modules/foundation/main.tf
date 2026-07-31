data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  name = "${var.project_name}-${var.environment}"
  tags = merge(var.tags, {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  })
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = merge(local.tags, { Name = "${local.name}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${local.name}-igw" })
}

resource "aws_subnet" "public" {
  for_each = { for index, az in var.availability_zones : az => {
    cidr  = var.public_subnet_cidrs[index]
    index = index
  } }

  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value.cidr
  map_public_ip_on_launch = true
  tags = merge(local.tags, {
    Name                     = "${local.name}-public-${each.key}"
    "kubernetes.io/role/elb" = "1"
  })
}

resource "aws_subnet" "private" {
  for_each = { for index, az in var.availability_zones : az => {
    cidr  = var.private_subnet_cidrs[index]
    index = index
  } }

  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value.cidr
  tags = merge(local.tags, {
    Name                              = "${local.name}-private-${each.key}"
    "kubernetes.io/role/internal-elb" = "1"
  })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = merge(local.tags, { Name = "${local.name}-public-rt" })
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.tags, { Name = "${local.name}-private-rt" })
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private.id
}

resource "aws_s3_bucket" "artifacts" {
  bucket_prefix = "${local.name}-artifacts-"
  force_destroy = false
  tags          = local.tags
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_public_access_block" "artifacts" {
  bucket                  = aws_s3_bucket.artifacts.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "events" {
  name         = "${local.name}-events"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "event_id"

  attribute {
    name = "event_id"
    type = "S"
  }
  ttl {
    attribute_name = "expires_at"
    enabled        = true
  }
  point_in_time_recovery {
    enabled = true
  }
  server_side_encryption {
    enabled = true
  }
  tags = local.tags
}

resource "aws_sqs_queue" "deployment_dlq" {
  name                        = "${local.name}-deployment-dlq.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  message_retention_seconds   = 1209600
  tags                        = local.tags
}

resource "aws_sqs_queue" "deployment" {
  name                        = "${local.name}-deployment.fifo"
  fifo_queue                  = true
  content_based_deduplication = true
  visibility_timeout_seconds  = 180
  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.deployment_dlq.arn
    maxReceiveCount     = 5
  })
  tags = local.tags
}

resource "aws_cloudwatch_event_bus" "deployment" {
  name = "${local.name}-deployment"
  tags = local.tags
}

resource "aws_cloudwatch_event_rule" "deployment_requested" {
  name           = "${local.name}-deployment-requested"
  event_bus_name = aws_cloudwatch_event_bus.deployment.name
  event_pattern = jsonencode({
    source      = ["portfolio.gitlab"]
    detail-type = ["GitLabDeploymentRequested"]
  })
  tags = local.tags
}

resource "aws_cloudwatch_event_target" "deployment_queue" {
  rule           = aws_cloudwatch_event_rule.deployment_requested.name
  event_bus_name = aws_cloudwatch_event_bus.deployment.name
  target_id      = "DeploymentQueue"
  arn            = aws_sqs_queue.deployment.arn
  sqs_target {
    message_group_id = "deployment-events"
  }
}

data "aws_iam_policy_document" "queue_policy" {
  statement {
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.deployment.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.deployment_requested.arn]
    }
  }
}

resource "aws_sqs_queue_policy" "deployment" {
  queue_url = aws_sqs_queue.deployment.id
  policy    = data.aws_iam_policy_document.queue_policy.json
}

data "archive_file" "webhook" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = "${path.module}/webhook_handler.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${local.name}-webhook-lambda"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "lambda_logs" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "lambda_permissions" {
  statement {
    actions   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.events.arn]
  }
  statement {
    actions   = ["events:PutEvents"]
    resources = [aws_cloudwatch_event_bus.deployment.arn]
  }
}

resource "aws_iam_role_policy" "lambda" {
  name   = "${local.name}-webhook-permissions"
  role   = aws_iam_role.lambda.id
  policy = data.aws_iam_policy_document.lambda_permissions.json
}

resource "aws_lambda_function" "webhook" {
  function_name    = "${local.name}-webhook"
  role             = aws_iam_role.lambda.arn
  handler          = "webhook_handler.handler"
  runtime          = "python3.13"
  filename         = data.archive_file.webhook.output_path
  source_code_hash = data.archive_file.webhook.output_base64sha256
  timeout          = 15
  memory_size      = 256

  environment {
    variables = {
      DDB_TABLE      = aws_dynamodb_table.events.name
      EVENT_BUS_NAME = aws_cloudwatch_event_bus.deployment.name
      WEBHOOK_SECRET = var.webhook_secret
    }
  }
  tags = local.tags
}

resource "aws_apigatewayv2_api" "webhook" {
  name          = "${local.name}-webhook"
  protocol_type = "HTTP"
  tags          = local.tags
}

resource "aws_apigatewayv2_integration" "webhook" {
  api_id                 = aws_apigatewayv2_api.webhook.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.webhook.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "webhook" {
  api_id    = aws_apigatewayv2_api.webhook.id
  route_key = "POST /webhooks/gitlab"
  target    = "integrations/${aws_apigatewayv2_integration.webhook.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.webhook.id
  name        = "$default"
  auto_deploy = true
  tags        = local.tags
}

resource "aws_lambda_permission" "api_gateway" {
  statement_id  = "AllowApiGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.webhook.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.webhook.execution_arn}/*/*"
}

