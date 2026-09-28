variable "project_name" {
  type    = string
  default = "rosa-gitlab"
}

variable "enable_nat_gateway" {
  description = "Enable the lab's shared NAT gateway. Disable only for Phase 1 without ROSA or when separately managing egress."
  type        = bool
  default     = true
}

variable "environment" {
  type    = string
  default = "dev"
}

variable "aws_region" {
  type    = string
  default = "ap-southeast-1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.40.0.0/16"
}

variable "availability_zones" {
  type = list(string)
  default = [
    "ap-southeast-1a",
    "ap-southeast-1b"
  ]
}

variable "webhook_secret" {
  type      = string
  sensitive = true
}
variable "public_subnet_cidrs" {
  type = list(string)
  default = [
    "10.40.0.0/24",
    "10.40.1.0/24"
  ]
}

variable "private_subnet_cidrs" {
  type = list(string)
  default = [
    "10.40.10.0/24",
    "10.40.11.0/24"
  ]
}
