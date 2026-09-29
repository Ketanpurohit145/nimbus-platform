provider "aws" {
  region = var.aws_region
}

# Networking: VPC with public subnets (EC2) and private subnets (RDS).
module "vpc" {
  source = "./modules/vpc"

  project_name    = var.project_name
  vpc_cidr        = var.vpc_cidr
  public_subnets  = var.public_subnets
  private_subnets = var.private_subnets
  aws_region      = var.aws_region
}

# Firewall rules: app SG allows SSH/HTTP/HTTPS in; DB SG only allows Postgres from the app SG.
module "security_groups" {
  source = "./modules/security_groups"

  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
  ssh_cidrs    = var.allowed_ssh_cidrs
}

# Single app server: EC2 instance running Flask/Gunicorn/Nginx, bootstrapped via user-data.
module "ec2" {
  source = "./modules/ec2"

  project_name          = var.project_name
  subnet_id             = module.vpc.public_subnet_ids[0]
  app_security_group_id = module.security_groups.app_sg_id
  instance_type         = var.instance_type
  key_name              = var.key_name
  public_key_path       = var.public_key_path
  ami_name_filter       = var.ami_name_filter
  app_port              = var.app_port
  aws_region            = var.aws_region
  db_name               = var.db_name
  db_admin_secret_arn   = module.rds.master_secret_arn
  db_app_secret_arn     = module.rds.app_secret_arn
  db_host               = module.rds.endpoint
  db_port               = module.rds.port
  domain_name           = var.domain_name
  certbot_email         = var.certbot_email
  log_group_names       = module.logging.log_group_names
  log_group_arns        = module.logging.log_group_arns
}

# Database: private, encrypted PostgreSQL RDS instance with an RDS-managed master password.
module "rds" {
  source = "./modules/rds"

  project_name         = var.project_name
  subnet_ids           = module.vpc.private_subnet_ids
  db_security_group_id = module.security_groups.db_sg_id
  db_name              = var.db_name
  db_username          = var.db_username
  db_instance_class    = var.db_instance_class
  db_allocated_storage = var.db_allocated_storage
}

# Alerting: CloudWatch CPU alarms for EC2/RDS, optionally emailed via SNS.
module "observability" {
  source = "./modules/observability"

  project_name            = var.project_name
  ec2_instance_id         = module.ec2.instance_id
  rds_instance_identifier = "${var.project_name}-postgres"
  notification_email      = var.alarm_notification_email
}

# Log groups that the EC2 CloudWatch Agent ships app/Nginx/bootstrap logs into.
module "logging" {
  source = "./modules/logging"

  project_name = var.project_name
}
