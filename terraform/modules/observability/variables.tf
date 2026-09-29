variable "project_name" {
  type = string
}

variable "ec2_instance_id" {
  type = string
}

variable "rds_instance_identifier" {
  type = string
}

variable "notification_email" {
  type    = string
  default = ""
}
