variable "project_name" {
  description = "Project name used in tagging and resource names"
  type        = string
  default     = "pilgrim"
}

variable "aws_region" {
  description = "AWS region for deployment"
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnets" {
  description = "Public subnet CIDR blocks"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]

  validation {
    condition     = length(var.public_subnets) >= 2
    error_message = "Provide at least two public subnets in distinct availability zones."
  }
}

variable "private_subnets" {
  description = "CIDR blocks for isolated private database subnets"
  type        = list(string)
  default     = ["10.0.11.0/24", "10.0.12.0/24"]

  validation {
    condition     = length(var.private_subnets) >= 2
    error_message = "Provide at least two private subnets in distinct availability zones."
  }
}

variable "instance_type" {
  description = "EC2 instance type used for the app"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Name of the EC2 SSH key pair to create from the local public key"
  type        = string
  default     = "pilgrim-key"
}

variable "public_key_path" {
  description = "Path to the local SSH public key to register with EC2"
  type        = string
  default     = "~/.ssh/pilgrim-key.pub"
}

variable "ami_name_filter" {
  description = "Ubuntu AMI filter for the selected region"
  type        = string
  default     = "ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"
}

variable "app_port" {
  description = "Port used by the Flask application"
  type        = number
  default     = 5000
}

variable "allowed_ssh_cidrs" {
  description = "Your trusted public IP CIDR(s) allowed to SSH, for example 203.0.113.10/32"
  type        = list(string)
}

variable "db_name" {
  description = "Database name for the RDS PostgreSQL instance"
  type        = string
  default     = "pilgrimdb"
}

variable "db_username" {
  description = "PostgreSQL master username"
  type        = string
  default     = "postgresadmin"
}

variable "db_instance_class" {
  description = "RDS instance class for the short review period"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_allocated_storage" {
  description = "RDS storage size in GB"
  type        = number
  default     = 20
}

variable "domain_name" {
  description = "Optional DNS name for enabling Let's Encrypt HTTPS on EC2"
  type        = string
  default     = ""

  validation {
    condition     = var.domain_name == "" || can(regex("^[A-Za-z0-9.-]+$", var.domain_name))
    error_message = "domain_name must be empty or a valid hostname without a scheme or path."
  }
}

variable "certbot_email" {
  description = "Email for Let's Encrypt certificate notices; required when domain_name is set"
  type        = string
  default     = ""

  validation {
    condition     = var.domain_name == "" || can(regex("^[^ @]+@[^ @]+\\.[^ @]+$", var.certbot_email))
    error_message = "Provide a valid certbot_email when domain_name is set."
  }
}

variable "alarm_notification_email" {
  description = "Optional email recipient for CloudWatch CPU alarm notifications"
  type        = string
  default     = ""

  validation {
    condition     = var.alarm_notification_email == "" || can(regex("^[^ @]+@[^ @]+\\.[^ @]+$", var.alarm_notification_email))
    error_message = "alarm_notification_email must be empty or a valid email address."
  }
}
