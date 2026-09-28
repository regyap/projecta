variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "availability_zones" {
  type = list(string)
  validation {
    condition     = length(var.availability_zones) > 0 && length(distinct(var.availability_zones)) == length(var.availability_zones)
    error_message = "Provide at least one Availability Zone, without duplicates."
  }
}

variable "enable_nat_gateway" {
  description = "Create one shared NAT gateway for private-subnet egress. Incurs AWS charges; required by this lab's default ROSA network."
  type        = bool
  default     = true
}

variable "public_subnet_cidrs" {
  type = list(string)
}

variable "private_subnet_cidrs" {
  type = list(string)
}

variable "lambda_source_dir" {
  type = string
}

variable "webhook_secret" {
  type      = string
  sensitive = true
}

variable "tags" {
  type    = map(string)
  default = {}
}
variable "aws_region" {
  type = string
}
