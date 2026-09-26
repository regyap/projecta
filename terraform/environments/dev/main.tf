provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Owner       = "R"
      CostCentre  = "Portfolio"
      AutoDestroy = "ReviewBeforeDeletion"
    }
  }
}

module "foundation" {
  source = "../../modules/foundation"

  project_name         = var.project_name
  environment          = var.environment
  aws_region           = var.aws_region
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  enable_nat_gateway   = var.enable_nat_gateway
  gitlab_oidc          = var.gitlab_oidc
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  webhook_secret       = var.webhook_secret
  lambda_source_dir    = "${path.root}/../../../lambda"
}


module "media" {
  count = var.enable_media_pipeline ? 1 : 0
  source = "../../modules/media"
  name = "${var.project_name}-${var.environment}"
  aws_region = var.aws_region
  source_dir = "${path.root}/../../../services/media"
  enable_geolocation = var.enable_geolocation
}
