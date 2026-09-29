resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-db-subnet-group"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# Placeholder secret; scripts/initialize_database.py fills in real app-user credentials on first deploy.
resource "aws_secretsmanager_secret" "app_credentials" {
  name                    = "${var.project_name}/app/database"
  recovery_window_in_days = 7

  tags = {
    Name = "${var.project_name}-app-database-credentials"
  }
}

# Ensures each destroy/recreate cycle gets a unique final-snapshot name (snapshot names can't be reused).
resource "random_id" "final_snapshot" {
  byte_length = 4
}

resource "aws_db_instance" "postgres" {
  identifier                  = "${var.project_name}-postgres"
  engine                      = "postgres"
  engine_version              = "15.19"
  instance_class              = var.db_instance_class
  allocated_storage           = var.db_allocated_storage
  db_name                     = var.db_name
  username                    = var.db_username
  manage_master_user_password = true # AWS creates/rotates the master password in a Secrets Manager secret (username+password only)
  db_subnet_group_name        = aws_db_subnet_group.main.name
  vpc_security_group_ids      = [var.db_security_group_id]
  publicly_accessible         = false
  storage_encrypted           = true
  copy_tags_to_snapshot       = true
  skip_final_snapshot         = false
  final_snapshot_identifier   = "${var.project_name}-final-${random_id.final_snapshot.hex}"
  backup_retention_period     = 1 # Free Plan restriction; a longer window would be preferred in production
  deletion_protection         = false

  tags = {
    Name = "${var.project_name}-postgres"
  }
}
