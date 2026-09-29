terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = { # used only to generate a unique RDS final-snapshot identifier
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
