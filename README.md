# Pilgrim Pantry

A Flask storefront with local SQLite development and Terraform-managed AWS infrastructure for a short review deployment.

## High-level architecture

Pilgrim Pantry is a Flask storefront deployed on one EC2 instance. Nginx proxies requests to Gunicorn/Flask; the app connects over TLS to a private PostgreSQL RDS instance. Terraform provisions the VPC, public and private subnets, Internet Gateway, route tables, security groups, EC2 IAM role, CloudWatch logs, and CPU alarms.

GitHub Actions runs tests and deploys successful `release-*` builds using a self-hosted runner on EC2. The `/health` endpoint checks database connectivity.

[View the document and high-level architecture diagram in Eraser](https://app.eraser.io/workspace/yWvo3DC7ZZ7t3eQi7uo8)

**Current-state note:** The saved Terraform state does not include an ALB, EKS, NAT Gateway, S3 bucket, or Route 53 resources. HTTPS is optional and is not enabled without a configured domain.

## Run locally

```bash
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
python app.py
```

Set a local-only `SECRET_KEY` in `.env`, then open `http://localhost:5000`. The `/health` route checks the configured database connection. `.env` is ignored by Git; `.env.example` is the safe template to commit.

## Project files

- `app.py`, `templates/`, and `static/` contain the Flask application.
- `requirements.txt` lists Flask, Gunicorn, PostgreSQL, and AWS SDK dependencies.
- `terraform/` contains the modular AWS infrastructure and EC2 bootstrap.
- `.github/workflows/ci.yml` runs Python checks and deploys release branches from a self-hosted runner.
- `docs/platform-engineering-assignment.md` is the separate assignment write-up; it is reference material, not the active app deployment workflow.

The deploy job calls `.github/workflows/deploy.sh` locally on the EC2-hosted self-hosted Linux x64 GitHub Actions runner. No database URL or SSH private key is stored in GitHub Actions: Terraform enables RDS-managed master credentials, and the EC2 instance role lets the initializer create a separate application DB user and store its credentials in Secrets Manager. The Flask process reads only the application secret. Keep the runner online and able to run the deployment's `sudo` commands. The instance role's Secrets Manager permissions are scoped to the RDS master secret and the named app secret; the host still needs master-secret access during app-user initialization, so move that setup to a separate administrative workflow before treating this as a production design.

The VPC has public subnets for the app EC2 and isolated private subnets for RDS. The PostgreSQL connections verify TLS against the RDS CA bundle. CloudWatch Logs receives Nginx, app, and bootstrap logs for seven days. CPU alarms use an 80% threshold for one one-minute datapoint; EC2 detailed monitoring is enabled to provide one-minute metrics. If `alarm_notification_email` is empty, alarms are visible in CloudWatch but do not send email.

HTTPS is prepared as an optional Certbot bootstrap path. It remains inactive until a domain name points to the EC2 public IP and `domain_name` plus `certbot_email` are set before instance creation. Without a domain, the demo uses HTTP only. RDS has one-day automated backup retention to satisfy the current Free Plan restriction, and Terraform requests a final snapshot on destroy; snapshots and Secrets Manager incur charges and survive longer than the running instance.

Do not commit real credentials or secret values. Set production environment variables outside the repository.

## EC2 SSH access

Create an SSH key locally; Terraform registers only its public key with AWS:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/pilgrim-key -C pilgrim-ec2
```

Set `allowed_ssh_cidrs` to your current public IP with a `/32` mask when Terraform prompts, then apply. Connect using the `ec2_public_ip` Terraform output:

```bash
ssh -i ~/.ssh/pilgrim-key ubuntu@<EC2_PUBLIC_IP>
```

Keep `~/.ssh/pilgrim-key` private and never commit it. If `pilgrim-key` already exists in AWS, import that key pair into Terraform state or choose a different `key_name` before applying.

## GitHub Actions deployment

After CI passes on a push to a `release-*` branch, the self-hosted runner copies the checked-out Flask files into `/opt/pilgrim/app`, installs Python requirements, initializes the application DB user if needed, enables/restarts the Gunicorn systemd service, reloads Nginx, and checks `/health`. The runner uses the EC2 instance profile for AWS access. Because the runner is on the target EC2 instance, no EC2 SSH or database URL secrets are needed in GitHub Actions.
