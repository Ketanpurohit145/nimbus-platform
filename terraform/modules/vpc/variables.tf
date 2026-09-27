variable "project_name" {
  description = "Project name used in tagging"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR for VPC"
  type        = string
}

variable "public_subnets" {
  description = "List of public subnet CIDRs"
  type        = list(string)
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}
