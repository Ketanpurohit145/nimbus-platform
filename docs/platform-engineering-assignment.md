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

Below are common risks and the mitigation steps.

### 1. Secrets stored in source code

Risk: credentials accidentally committed to Git.

Fix:
- Use `.env` files outside source control.
- Store secrets in AWS Secrets Manager or GitHub Actions secrets.
- Add `.env` to `.gitignore`.

### 2. Overly permissive IAM access

Risk: broad permissions allow lateral movement.

Fix:
- Follow least privilege.
- Use IAM roles for EC2 and other AWS services.
- Restrict Access Keys and rotate them regularly.

### 3. Publicly exposed database

Risk: RDS instance accessible from the internet.

Fix:
- Place RDS in a private subnet.
- Only allow access from the application security group.
- Disable public access.

### 4. Open security group ports

Risk: unnecessary ports exposed to the internet.

Fix:
- Open only 22, 80, and 443 as required.
- Restrict SSH access to approved IPs.
- Use ALB for public access and keep EC2 private when possible.

### 5. Missing SSL

Risk: data theft or insecure connections.

Fix:
- Use Nginx with Let’s Encrypt.
- Redirect HTTP to HTTPS.
- Enable HSTS if supported.

### 6. Debug mode enabled

Risk: application reveals stack traces or sensitive info.

Fix:
- Set `NODE_ENV=production` or `DEBUG=False`.
- Disable detailed error pages in production.

### 7. Outdated dependencies

Risk: known vulnerabilities.

Fix:
- Run dependency update checks regularly.
- Use `npm audit`, `pip-audit`, or Snyk.
- Patch vulnerable libraries promptly.

### 8. Weak Linux permissions

Risk: code and config readable by unauthorized users.

Fix:
- Use dedicated application user.
- Restrict `.env` and config file permissions.
- Avoid running as root.

### 9. Missing backups

Risk: losing the database or app state after a failure.

Fix:
- Enable automated RDS snapshots.
- Backup code repositories and artifact versions.
- Test restoration procedures regularly.

### 10. Missing monitoring and alerts

Risk: incidents go unnoticed.

Fix:
- Use CloudWatch alarms.
- Monitor CPU, memory, disk, 5xx errors, and HTTP latency.
- Configure alerts via email or SMS.

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
