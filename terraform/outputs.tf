output "vpc_id" {
  description = "Created VPC ID"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = module.vpc.public_subnet_ids
}

output "ec2_public_ip" {
  description = "Public IP of the app EC2 instance"
  value       = module.ec2.public_ip
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = module.rds.endpoint
}

output "app_url" {
  description = "Application URL for the deployed service"
  value       = var.domain_name == "" ? "http://${module.ec2.public_ip}" : "https://${var.domain_name}"
}
