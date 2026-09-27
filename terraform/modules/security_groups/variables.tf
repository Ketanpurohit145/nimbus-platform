variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "ssh_cidrs" {
  type = list(string)
}
