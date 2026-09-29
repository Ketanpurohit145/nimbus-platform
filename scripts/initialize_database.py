#!/usr/bin/env python3
# Runs once per deploy (idempotent) to create/rotate the limited-privilege app DB user and store its credentials.
import json
import logging
import os
import secrets

import boto3
import psycopg2
from botocore.exceptions import BotoCoreError, ClientError
from psycopg2 import sql

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def required_environment(name):
    # Fail fast with a clear error instead of a confusing downstream KeyError/None if config is missing.
    value = os.getenv(name)
    if not value:
        raise RuntimeError(f"Required environment variable {name} is missing")
    return value


def main():
    region = required_environment("AWS_REGION")
    admin_secret_arn = required_environment("DB_ADMIN_SECRET_ARN")
    app_secret_arn = required_environment("DB_APP_SECRET_ARN")
    database_name = required_environment("DATABASE_NAME")
    # DB_HOST/DB_PORT come from Terraform (via app.env), NOT the RDS-managed secret, which only holds username/password.
    db_host = required_environment("DB_HOST")
    db_port = int(required_environment("DB_PORT"))
    app_username = os.getenv("DB_APP_USERNAME", "pilgrim_app")

    secrets_manager = boto3.client("secretsmanager", region_name=region)
    try:
        app_secret_metadata = secrets_manager.describe_secret(SecretId=app_secret_arn)
        if any(
            "AWSCURRENT" in stages
            for stages in app_secret_metadata.get("VersionIdsToStages", {}).values()
        ):
            # App credentials already exist from a prior deploy; skip re-creating the role/password.
            logger.info("Application database credentials are already initialized")
            return

        # Use the RDS master (admin) credentials only long enough to provision the limited app-user role.
        admin_secret = secrets_manager.get_secret_value(SecretId=admin_secret_arn)
        admin_credentials = json.loads(admin_secret["SecretString"])
        app_password = secrets.token_urlsafe(40)

        with psycopg2.connect(
            host=db_host,
            port=db_port,
            dbname=database_name,
            user=admin_credentials["username"],
            password=admin_credentials["password"],
            sslmode="verify-full",
            sslrootcert="/etc/ssl/certs/rds-global-bundle.pem",
            connect_timeout=10,
        ) as connection:
            with connection.cursor() as cursor:
                # Create the app role on first run, or rotate its password if it already exists.
                cursor.execute("SELECT 1 FROM pg_roles WHERE rolname = %s", (app_username,))
                role_exists = cursor.fetchone() is not None
                role_command = "ALTER ROLE" if role_exists else "CREATE ROLE"
                cursor.execute(
                    sql.SQL("{} {} LOGIN PASSWORD {}").format(
                        sql.SQL(role_command),
                        sql.Identifier(app_username),
                        sql.Literal(app_password),
                    )
                )
                # Grant only what the Flask app needs: connect, and CRUD on existing tables/sequences.
                cursor.execute(
                    sql.SQL("GRANT CONNECT ON DATABASE {} TO {}").format(
                        sql.Identifier(database_name),
                        sql.Identifier(app_username),
                    )
                )
                cursor.execute(
                    sql.SQL("GRANT USAGE, CREATE ON SCHEMA public TO {}").format(
                        sql.Identifier(app_username)
                    )
                )
                cursor.execute(
                    sql.SQL(
                        "GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO {}"
                    ).format(sql.Identifier(app_username))
                )
                cursor.execute(
                    sql.SQL(
                        "GRANT USAGE, SELECT, UPDATE ON ALL SEQUENCES IN SCHEMA public TO {}"
                    ).format(sql.Identifier(app_username))
                )

        # Persist the new app-user credentials so the running Flask app can read them via boto3 at startup.
        app_credentials = {
            "username": app_username,
            "password": app_password,
            "host": db_host,
            "port": db_port,
            "dbname": database_name,
        }
        secrets_manager.put_secret_value(
            SecretId=app_secret_arn,
            SecretString=json.dumps(app_credentials),
        )
        logger.info("Application database credentials initialized")
    except (BotoCoreError, ClientError, KeyError, ValueError, psycopg2.Error):
        logger.exception("Application database initialization failed")
        raise


if __name__ == "__main__":
    main()
