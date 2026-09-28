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
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  webhook_secret       = var.webhook_secret
  lambda_source_dir    = "${path.root}/../../../lambda"
}

