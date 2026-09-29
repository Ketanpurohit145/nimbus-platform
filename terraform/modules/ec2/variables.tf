variable "project_name" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "app_security_group_id" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "key_name" {
  type = string
}

variable "public_key_path" {
  type = string
}

variable "ami_name_filter" {
  type = string
}

variable "app_port" {
  type = number
}

variable "aws_region" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_admin_secret_arn" {
  type = string
}

variable "db_app_secret_arn" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "certbot_email" {
  type = string
}

variable "log_group_names" {
  type = map(string)
}

variable "log_group_arns" {
  type = list(string)
}
