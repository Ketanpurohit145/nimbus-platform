variable "project_name" {
  type = string
}

variable "subnet_ids" { # private subnets only; RDS has no internet route
  type = list(string)
}

variable "db_security_group_id" {
  type = string
}

variable "db_name" {
  type = string
}

variable "db_username" { # master username; password is managed automatically via Secrets Manager
  type = string
}

variable "db_instance_class" {
  type = string
}

variable "db_allocated_storage" {
  type = number
}
