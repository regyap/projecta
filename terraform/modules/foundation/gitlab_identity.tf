variable "gitlab_oidc" {
  description = "Existing verified GitLab OIDC provider and exact protected-branch subject; null creates no CI AWS role."
  type = object({
    provider_arn = string
    issuer       = string
    project_path = string
    branch       = string
  })
  default = null
  validation {
    condition = var.gitlab_oidc == null ? true : (
      startswith(var.gitlab_oidc.issuer, "https://") &&
      !endswith(var.gitlab_oidc.issuer, "/") &&
      !strcontains(var.gitlab_oidc.project_path, "*") &&
      !strcontains(var.gitlab_oidc.branch, "*") &&
      length(var.gitlab_oidc.project_path) > 0 && length(var.gitlab_oidc.branch) > 0
    )
    error_message = "Use an HTTPS issuer without trailing slash and an exact project/branch, without wildcards."
  }
}
data "aws_iam_policy_document" "gitlab_trust" {
  count = var.gitlab_oidc == null ? 0 : 1
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]
    principals {
      type        = "Federated"
      identifiers = [var.gitlab_oidc.provider_arn]
    }
    condition {
      test     = "StringEquals"
      variable = "${trimprefix(var.gitlab_oidc.issuer, "https://")}:aud"
      values   = ["sts.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "${trimprefix(var.gitlab_oidc.issuer, "https://")}:sub"
      values   = ["project_path:${var.gitlab_oidc.project_path}:ref_type:branch:ref:${var.gitlab_oidc.branch}"]
    }
  }
}
resource "aws_iam_role" "gitlab_artifacts" {
  count                = var.gitlab_oidc == null ? 0 : 1
  name                 = "${local.name}-gitlab-artifact-writer"
  assume_role_policy   = data.aws_iam_policy_document.gitlab_trust[0].json
  max_session_duration = 3600
  tags                 = local.tags
}
data "aws_iam_policy_document" "gitlab_artifacts" {
  count = var.gitlab_oidc == null ? 0 : 1
  statement {
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.artifacts.arn}/ci/*"]
  }
}
resource "aws_iam_role_policy" "gitlab_artifacts" {
  count  = var.gitlab_oidc == null ? 0 : 1
  role   = aws_iam_role.gitlab_artifacts[0].id
  policy = data.aws_iam_policy_document.gitlab_artifacts[0].json
}
output "gitlab_artifact_role_arn" { value = try(aws_iam_role.gitlab_artifacts[0].arn, null) }
