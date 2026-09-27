# Pilgrim Pantry

A Flask storefront with local SQLite development and Terraform-managed AWS infrastructure for a short review deployment.

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
- `requirements.txt` lists the Flask, Gunicorn, and PostgreSQL dependencies.
- `terraform/` contains the modular AWS infrastructure and EC2 bootstrap.
- `.github/workflows/ci.yml` runs Python checks and deploys `main` from a self-hosted runner.
- `docs/platform-engineering-assignment.md` is the separate assignment write-up; it is reference material, not the active app deployment workflow.

The deploy job calls `.github/workflows/deploy.sh` locally on the EC2-hosted self-hosted Linux x64 GitHub Actions runner. Configure the repository Actions secret `DATABASE_URL` before pushing to a `release-*` branch. The runner must be installed on the app EC2 instance, online, and able to run the deployment's `sudo` commands.

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

After CI passes on a push to a `release-*` branch, the self-hosted runner copies the checked-out Flask files into `/opt/pilgrim/app`, writes the database URL to a root-owned environment file, installs Python requirements, enables/restarts the Gunicorn systemd service, reloads Nginx, and checks `/health`. URL-encode special characters in the database password when constructing `DATABASE_URL`. The database URL is passed as a GitHub Actions secret and is not written to the repository. Because the runner is on the target EC2 instance, no EC2 SSH secrets are needed for deployment.
