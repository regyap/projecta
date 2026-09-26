mock_provider "aws" {
  mock_data "aws_caller_identity" { defaults = { account_id = "123456789012" } }
  mock_data "aws_partition" { defaults = { partition = "aws" } }
}
mock_provider "archive" {}
variables {
  name = "rosa-test"
  aws_region = "ap-southeast-1"
  source_dir = "../../../services/media"
}
run "media_without_location" {
  command = plan
  module { source = "../../modules/media" }
  assert {
    condition = aws_sqs_queue.images.sqs_managed_sse_enabled && aws_sqs_queue.images.visibility_timeout_seconds >= 6 * aws_lambda_function.worker.timeout
    error_message = "Queue must be encrypted and visibility must allow Lambda retry time."
  }
  assert {
    condition = aws_s3_bucket_public_access_block.media.block_public_policy && aws_s3_bucket_public_access_block.media.restrict_public_buckets
    error_message = "Media must not be publicly accessible."
  }
  assert {
    condition = aws_lambda_function.worker.environment[0].variables["ENABLE_GEOLOCATION"] == "false"
    error_message = "Geolocation must be opt-in."
  }
  assert {
    condition = aws_s3_bucket_versioning.media.versioning_configuration[0].status == "Enabled"
    error_message = "Worker must process immutable input versions."
  }
}
run "media_with_location" {
  command = plan
  module { source = "../../modules/media" }
  variables { enable_geolocation = true }
  assert {
    condition = aws_lambda_function.worker.environment[0].variables["ENABLE_GEOLOCATION"] == "true"
    error_message = "Explicit opt-in must reach the worker configuration."
  }
}
