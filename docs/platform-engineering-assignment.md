# Platform Engineer – Technical Assignment

## Overview

This assignment evaluates practical ownership of deployment operations, production troubleshooting, AWS infrastructure, security, and the ability to make small backend changes when needed. The solution below is structured to be usable as a written answer and as a documentation package for a platform engineering role.

---

## Part 1: Deployment Approach

### 1. Server setup and package installation

I would launch a Linux EC2 instance such as Ubuntu 22.04 LTS, apply a security group, attach an IAM role if needed, and install the required packages.

Example commands:

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install -y git curl nginx certbot python3-certbot-nginx build-essential
sudo apt install -y postgresql-client
```

If the application is Node.js based:

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs
sudo npm install -g pm2
```

If the application is Django/Python based:

```bash
sudo apt install -y python3 python3-pip python3-venv libpq-dev
python3 -m venv /var/www/platform/venv
```

### 2. Application directory structure

A clean application layout helps deployment and rollback.

```text
/var/www/
└── platform/
    ├── app/
    ├── config/
    ├── logs/
    ├── .env
    ├── .env.example
    ├── package.json
    ├── server.js
    ├── src/
    └── releases/
```

A more production-friendly layout may use:

```text
/var/www/platform/current
/var/www/platform/releases/20260927_120000
/var/www/platform/shared/.env
```

### 3. Environment variable management

Environment variables should never be committed to source control. Use a local `.env` file with restricted permissions.

```bash
sudo nano /var/www/platform/.env
chmod 600 /var/www/platform/.env
```

Example:

```env
NODE_ENV=production
PORT=3000
DB_HOST=prod-db.xxxxxx.us-east-1.rds.amazonaws.com
DB_PORT=5432
DB_NAME=platformdb
DB_USER=platformuser
DB_PASSWORD=strong-password
JWT_SECRET=secret
SESSION_SECRET=secret
```

### 4. Dependency installation

For Node.js application:

```bash
cd /var/www/platform
npm install --production
```

For Python/Django:

```bash
source /var/www/platform/venv/bin/activate
pip install -r requirements.txt
```

### 5. Application server configuration

For Node.js, I would usually run the app with PM2:

```bash
pm2 start server.js --name platform --env production
pm2 save
pm2 startup
```

If using a systemd unit (recommended for reliability):

```ini
[Unit]
Description=Platform App
After=network.target

[Service]
User=ubuntu
WorkingDirectory=/var/www/platform
EnvironmentFile=/var/www/platform/.env
ExecStart=/usr/bin/node /var/www/platform/server.js
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable platform
sudo systemctl start platform
```

### 6. Nginx configuration

Nginx should reverse proxy to the app and terminate TLS.

```nginx
server {
    listen 80;
    server_name app.example.com;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name app.example.com;

    ssl_certificate /etc/letsencrypt/live/app.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/app.example.com/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

### 7. SSL certificate setup

Use Let’s Encrypt to issue a certificate automatically.

```bash
sudo certbot --nginx -d app.example.com
```

Set up automatic renewal:

```bash
sudo systemctl status certbot.timer
sudo certbot renew --dry-run
```

### 8. Application startup and restart process

For PM2:

```bash
pm2 restart platform
pm2 logs platform
```

For systemd:

```bash
sudo systemctl restart platform
sudo systemctl status platform
```

### 9. Log locations

Common locations:

```bash
/var/log/nginx/access.log
/var/log/nginx/error.log
/var/www/platform/logs/app.log
/var/www/platform/logs/app-error.log
```

### 10. Deployment rollback approach

A safe rollback process is essential.

```bash
cd /var/www/platform
git fetch origin
git checkout <previous-good-tag>
# or restore previous release path from /releases
pm2 restart platform
```

Best practice: keep backups of the last working release and DB migration history so an emergency rollback can be performed quickly.

---

## Part 2: CI/CD Pipeline

Below is a sample GitHub Actions workflow for deployment to an EC2 server.

```yaml
name: Deploy to EC2

on:
  push:
    branches:
      - main

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Node.js
        uses: actions/setup-node@v4
        with:
          node-version: 20

      - name: Install dependencies
        run: npm ci

      - name: Run tests
        run: npm test -- --runInBand

  deploy:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Deploy over SSH
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.EC2_HOST }}
          username: ${{ secrets.EC2_USER }}
          key: ${{ secrets.EC2_SSH_KEY }}
          script: |
            set -e
            cd /var/www/platform
            git pull origin main
            npm ci --production
            npm run migrate
            pm2 restart platform
            sudo nginx -t
            sudo systemctl reload nginx
            curl -f http://127.0.0.1:3000/health
```

### Pipeline workflow summary

1. Trigger on push to main branch.
2. Run unit/integration tests.
3. Connect securely to EC2 using SSH keys stored in GitHub secrets.
4. Pull latest changes.
5. Install dependencies.
6. Run database migrations.
7. Restart the app.
8. Check health endpoint.
9. If health check fails, stop the release and roll back.

### Rollback logic

The deployment job should fail fast if the health check does not return success. The pipeline should then:

- restore the previous release directory,
- restart the last known good version,
- verify again,
- notify the team.

---

## Part 3: Production Incident Investigation

### Symptom

Users receive a `502 Bad Gateway` error after a deployment.

### Investigation steps

#### 1. Check Nginx status

```bash
sudo systemctl status nginx
sudo nginx -t
sudo tail -n 200 /var/log/nginx/error.log
sudo tail -n 200 /var/log/nginx/access.log
```

#### 2. Check app service status

```bash
sudo systemctl status platform
sudo journalctl -u platform -n 200 --no-pager
```

#### 3. Check process and port state

```bash
ps -ef | grep node
ss -lntup | grep 3000
lsof -i :3000
```

#### 4. Check app logs

```bash
tail -n 200 /var/www/platform/logs/app.log
tail -n 200 /var/www/platform/logs/app-error.log
```

#### 5. Check permissions and file ownership

```bash
ls -ld /var/www/platform
ls -l /var/www/platform
sudo chown -R ubuntu:ubuntu /var/www/platform
```

#### 6. Check database connectivity

```bash
psql "host=... port=5432 dbname=... user=..." -c "SELECT 1;"
```

### Common root causes for 502

- Application process crashed or failed to start.
- Wrong port binding or app not listening.
- Nginx proxy configuration points to the wrong backend address.
- Database connectivity issue or migration failure.
- Missing environment variables.
- File permission errors.
- Old build artifact or broke syntax introducing runtime failures.
- Excessive app memory causing process restart loops.

### Steps to restore the application safely

1. Identify the failing service or port.
2. Review app logs and Nginx logs.
3. Fix config or environment issues.
4. Restart the app service.
5. Validate health endpoint.
6. Check database connectivity.
7. Reload Nginx.
8. If needed, revert to the previous stable deployment.

---

## Part 4: Security Review

The implementation uses a short-lived review environment, so the following controls are included in Terraform and the deployment design. Items that require a domain or a notification recipient are explicitly conditional.

### 1. Secrets and database credentials

The RDS master password is generated and rotated by RDS through Secrets Manager rather than supplied as a Terraform variable. The deployment initializer creates a separate `pilgrim_app` database user and places that credential in a second Secrets Manager secret. The Flask process retrieves the app credential through the EC2 instance profile. PostgreSQL connections use TLS certificate verification against the RDS CA bundle. Neither the master password nor the database URL is committed or passed as a GitHub Actions secret.

Terraform state and any saved plan files must still be treated as sensitive. The EC2 role's Secrets Manager access is scoped to the RDS master secret and the named application secret. The deployment initializer needs master-secret access to provision the limited application user; for a larger production system, move this one-time database provisioning into an isolated administrative workflow so the long-running app host never has master-secret access.

### 2. IAM access

The EC2 instance has an instance profile rather than static AWS access keys. Its role permits CloudWatch log publishing and the Secrets Manager operations required by the database initializer and application. Do not grant administrator access or reuse a human IAM user's access keys on EC2.

### 3. Database and network isolation

RDS is configured with public access disabled and is placed in private subnets that have no internet route. Its security group accepts PostgreSQL traffic only from the application security group. The public EC2 host accepts HTTP and HTTPS traffic; SSH is restricted to the operator's configured CIDR.

### 4. Transport security

Nginx is the public reverse proxy and Gunicorn listens only on loopback. Certbot support is included, but trusted HTTPS is not active until an owned DNS name points to EC2 and a contact email is provided. Until then, the demo is HTTP-only and must not collect real personal or payment information.

### 5. Production debug and Linux permissions

The production service runs Gunicorn with Flask debug mode disabled and runs as the dedicated `pilgrim` user. Runtime configuration is kept in `/etc/pilgrim/app.env`, owned by root and readable only by the application group. The application does not run as root.

### 6. Dependency and deployment risks

Python dependencies are pinned in `requirements.txt`. A vulnerability scan and routine patch process should be added before production use. The self-hosted GitHub Actions runner is on the app EC2 host and deployment uses `sudo`; this increases the impact of a compromised workflow. Restrict who can modify release workflows and keep the runner dedicated to this trusted repository.

### 7. Backups and deletion

RDS storage is encrypted, automated backups are retained for one day to satisfy the current Free Plan restriction, and Terraform requests a final snapshot during destroy. A final snapshot and scheduled deletion of the application secret can continue to incur charges after the EC2 and RDS instance are removed. Deletion protection remains disabled for this short-lived demo, so operators must review the destroy plan and retain snapshots intentionally.

### 8. Monitoring and log retention

The CloudWatch Agent ships app, Nginx, and bootstrap logs to CloudWatch Logs with seven-day retention. EC2 and RDS CPU alarms trigger above 80% for one one-minute datapoint. EC2 detailed monitoring is enabled for one-minute metrics and may incur additional charges. Email delivery is optional and requires setting `alarm_notification_email` and confirming the SNS subscription.

---

## Part 5: Small Code Change

Below is a simple Express.js health-check endpoint that returns `200` when the app is running and returns a `503` if the database is unavailable.

```js
const express = require('express');
const { Pool } = require('pg');

const app = express();
const port = process.env.PORT || 3000;

const pool = new Pool({
  host: process.env.DB_HOST,
  port: process.env.DB_PORT || 5432,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
  database: process.env.DB_NAME,
});

app.get('/health', async (req, res) => {
  try {
    const client = await pool.connect();
    await client.query('SELECT 1');
    client.release();

    return res.status(200).json({
      status: 'ok',
      service: 'platform',
      database: 'connected',
    });
  } catch (error) {
    return res.status(503).json({
      status: 'error',
      service: 'platform',
      database: 'unavailable',
      message: 'Database connection failed',
    });
  }
});

app.listen(port, () => {
  console.log(`App listening on port ${port}`);
});
```

This health check can be used by nginx, the deployment pipeline, or CloudWatch alarms for verification.

### Django example

```python
from django.http import JsonResponse
from django.db import connection
from django.views.decorators.csrf import csrf

@csrf.csrf
def healthcheck(request):
    try:
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
        return JsonResponse({"status": "ok", "database": "connected"}, status=200)
    except Exception:
        return JsonResponse({"status": "error", "database": "unavailable"}, status=503)
```

---

## Part 6: AWS Architecture

### Recommended architecture

- EC2: hosts the application and runs Node.js or Python app.
- RDS PostgreSQL: stores application data.
- Application Load Balancer: distributes traffic and provides TLS termination.
- IAM: restricts EC2, RDS, and deployment role permissions.
- Security Groups: allow only needed ports and traffic paths.
- S3: stores static assets, backups, logs, or artifacts.
- CloudWatch: monitors CPU, RAM, disk, 5xx errors, logs, and alarms.
- Route 53: manages DNS and health checks.
- Backups: automate RDS snapshots and configure retention policies.
- Monitoring and alerts: alert on failed deploys, CPU saturation, DB latency, and app errors.

### Example architecture diagram

```text
Internet
   |
   v
Route 53
   |
   v
ALB
   |
   +--> EC2 App Server 1
   +--> EC2 App Server 2
            |
            v
        RDS PostgreSQL
            |
            v
         S3 (static assets / backups)

CloudWatch monitors logs, metrics, and alarms
```

### Best practices

- Keep EC2 instances behind an ALB.
- Keep database in a private subnet.
- Use IAM roles instead of hard-coded credentials.
- Store secrets in AWS Secrets Manager.
- Set CloudWatch alarms for 5xx errors, CPU, memory, and service health.
- Enable automated backups for PostgreSQL.
- Use multi-AZ for high availability when possible.

---

## Final Deliverable Notes

To submit the assignment, I would prepare:

- a PDF, Markdown, or Google Doc version of this answer,
- sample config files,
- CI/CD pipeline file,
- health-check code sample,
- and a simple architecture diagram in Mermaid or a diagram tool.

This can then be uploaded as a public Google Doc or shared as a public Google Sheet link, with no real secrets or credentials included.

---

## Short summary for a project proposal

For this platform, I would host the service on Ubuntu EC2 instances behind an ALB, use RDS PostgreSQL for persistence, manage secrets securely, deploy with a GitHub Actions pipeline, use Nginx for reverse proxying and TLS, and set up CloudWatch monitoring and health checks for production reliability. The application would be deployed with automated rollback logic, a secure baseline, and a health-check endpoint to quickly detect app or database failures.
