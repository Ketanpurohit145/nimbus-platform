output "endpoint" { # threaded into app.env as DB_HOST since the master secret omits it
  value = aws_db_instance.postgres.address
}

output "port" {
  value = aws_db_instance.postgres.port
}

output "master_secret_arn" { # RDS-managed admin credentials, used only by initialize_database.py
  value = aws_db_instance.postgres.master_user_secret[0].secret_arn
}

output "app_secret_arn" { # least-privilege app-user credentials, used by the running Flask app
  value = aws_secretsmanager_secret.app_credentials.arn
}
