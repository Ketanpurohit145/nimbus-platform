variable "project_name" { # used for naming/tagging resources
  type = string
}

variable "subnet_id" { # public subnet the instance launches into
  type = string
}

variable "app_security_group_id" {
  type = string
}

variable "instance_type" {
  type = string
}

variable "key_name" { # name registered for the SSH key pair
  type = string
}

variable "public_key_path" { # local path to the SSH public key uploaded to AWS
  type = string
}

variable "ami_name_filter" { # AMI name pattern used to look up the latest Ubuntu image
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

variable "db_admin_secret_arn" { # RDS-managed master credentials (username/password only)
  type = string
}

variable "db_host" { # RDS endpoint, passed separately since the secret doesn't include it
  type = string
}

variable "db_port" {
  type = number
}

variable "db_app_secret_arn" { # least-privilege app-user credentials created by scripts/initialize_database.py
  type = string
}

variable "domain_name" { # optional; enables Certbot/TLS in bootstrap.sh when set
  type = string
}

variable "certbot_email" {
  type = string
}

variable "log_group_names" { # CloudWatch log group names the agent config in bootstrap.sh writes to
  type = map(string)
}

variable "log_group_arns" { # scopes the EC2 IAM role's CloudWatch Logs permissions
  type = list(string)
}
