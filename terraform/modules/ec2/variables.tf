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
