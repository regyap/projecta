mock_provider "aws" {
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}
mock_provider "archive" {}

variables {
  project_name         = "rosa-test"
  environment          = "test"
  aws_region           = "ap-southeast-1"
  vpc_cidr             = "10.40.0.0/16"
  availability_zones   = ["ap-southeast-1a", "ap-southeast-1b"]
  public_subnet_cidrs   = ["10.40.0.0/24", "10.40.1.0/24"]
  private_subnet_cidrs  = ["10.40.10.0/24", "10.40.11.0/24"]
  webhook_secret       = "test-only-placeholder"
  lambda_source_dir    = "../../../lambda"
}

run "nat_enabled" {
  command = plan
  module {
    source = "../../modules/foundation"
  }
  assert {
    condition     = length(aws_nat_gateway.this) == 1 && length(aws_eip.nat) == 1 && length(aws_route.private_default) == 1
    error_message = "The default lab configuration must create one NAT, EIP and private default route."
  }
  assert {
    condition     = aws_route.private_default[0].destination_cidr_block == "0.0.0.0/0"
    error_message = "NAT egress must cover the IPv4 default route."
  }
  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.private) == 2 && length(aws_route_table_association.private) == 2
    error_message = "Both AZ subnet pairs must retain private route-table associations."
  }
  assert {
    condition     = aws_vpc.this.enable_dns_support && aws_vpc.this.enable_dns_hostnames
    error_message = "ROSA needs VPC DNS support and hostnames."
  }
}

run "nat_disabled" {
  command = plan
  module {
    source = "../../modules/foundation"
  }
  variables {
    enable_nat_gateway = false
  }
  assert {
    condition     = length(aws_nat_gateway.this) == 0 && length(aws_eip.nat) == 0 && length(aws_route.private_default) == 0
    error_message = "Opting out must omit NAT, its EIP and its private default route."
  }
  assert {
    condition     = length(aws_subnet.public) == 2 && length(aws_subnet.private) == 2
    error_message = "Disabling NAT must preserve existing subnets."
  }
}
