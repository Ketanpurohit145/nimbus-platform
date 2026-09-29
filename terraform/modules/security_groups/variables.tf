variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "ssh_cidrs" { # CIDR blocks allowed to SSH into the app instance; keep this tight
  type = list(string)
}
