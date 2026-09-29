aws freetier get-account-plan-state --region us-east-1
aws freetier get-free-tier-usage --region us-east-1# Platform Engineering Assignment: Completion Checklist

Status key:
- [x] Implemented in the project
- [~] Partially implemented or needs verification
- [ ] Pending

## Current project status

- [x] Flask storefront displays menu items and records orders, order items, totals, and stock updates.
- [x] Local development uses SQLite; the app accepts a PostgreSQL `DATABASE_URL`.
- [x] `/health` checks database connectivity and returns HTTP 503 when the database is unavailable.
- [x] Terraform is split into VPC, security-group, EC2, RDS, logging, and observability modules.
- [x] EC2 bootstrap installs Python, Git, Nginx, Certbot, and the CloudWatch Agent and creates the application user and virtual environment.
- [x] Gunicorn is managed by systemd; Nginx proxies HTTP traffic to the local Gunicorn listener.
- [x] GitHub Actions runs basic Flask smoke checks and has a release-branch deployment job.
- [x] The deployment script installs requirements, initializes a limited application database user, restarts the service, and checks local health.
- [x] The deployment job uses a self-hosted runner on the app EC2 instance. Runner is now installed as a systemd service (`svc.sh install` + `start`) so it survives instance stop/start and reboot; confirmed `online` via the GitHub API.
- [x] AWS infrastructure has been recreated. EC2 and RDS were verified running/available after apply. A release-branch deployment (`5ea2fa9`) completed successfully end-to-end: CI test job passed, deploy job passed, `/health` returns `{"database":"connected","status":"ok"}`, and the homepage serves the real Flask storefront (not the Nginx default page) at the current public IP.

## Part 1: Deployment approach

- [x] Ubuntu EC2 bootstrap and required OS packages.
- [x] Dedicated application user and `/opt/pilgrim` application layout.
- [x] Python dependencies declared in `requirements.txt`, including Flask, Gunicorn, SQLAlchemy, and PostgreSQL driver.
- [x] Production process managed by systemd and served through Nginx.
- [x] Runtime configuration is stored on EC2 with restricted permissions; the RDS master password is managed by RDS and stored in Secrets Manager rather than passed as a Terraform variable.
- [x] Application and Nginx logs can be inspected through systemd journal and Nginx log files.
- [~] HTTPS bootstrap is prepared but inactive until a domain and DNS record are available. Without a domain, the demo remains HTTP-only.
- [ ] Deployment rollback is not implemented. The current deployment replaces files in place and restarts the service.
- [~] The Security Review section now describes Flask and the implemented controls, but the deployment, CI/CD, and 502 sections still contain Node/Django/PM2 examples and need alignment.

## Part 2: CI/CD

- [x] GitHub Actions runs on pushes to `main` and `release-*`; pull requests to `main` run the test job.
- [x] Deployment is gated to pushes on `release-*` and waits for the test job.
- [x] CI installs Python requirements, compiles the app, and smoke-tests the home and health endpoints.
- [x] Deployment runs on a self-hosted EC2 runner, so it does not need SSH credentials to connect back to that same instance.
- [x] Deployment retrieves DB credentials through the EC2 role and Secrets Manager (`DB_HOST`/`DB_PORT` come from Terraform-provided values in `/etc/pilgrim/app.env`, not the RDS-managed secret, since that secret only contains `username`/`password`). The EC2 runner service remains online after the stack is recreated (verified as a systemd service).
- [ ] Add an automated order-placement test and PostgreSQL-backed integration test; current CI smoke tests use local SQLite.
- [ ] Add database migration handling before schema changes are released.
- [ ] Add deployment rollback or previous-release restoration when the post-deploy health check fails.
- [ ] Document and review the security implications of running a self-hosted Actions runner with deployment `sudo` access on the app server.

## Part 3: 502 incident investigation

- [~] The assignment includes an investigation procedure, but its commands still use stale Node/PM2, port 3000, and `/var/www/platform` paths.
- [ ] Rewrite the runbook for Nginx, `pilgrim.service`, Gunicorn on `127.0.0.1:5000`, `/opt/pilgrim/app`, systemd journal, and the actual health route.
- [ ] Include an external check through Nginx on port 80 and a database connectivity check that does not expose credentials.

## Part 4: Security and operations

- [x] `.env`, Terraform state, local Terraform files, Python virtual environments, and private-key files are excluded by `.gitignore`.
- [x] RDS is configured as not publicly accessible, is placed in isolated private subnets, and its security group accepts PostgreSQL only from the app security group.
- [x] SSH is configurable as a restricted CIDR; app traffic uses Nginx rather than exposing Gunicorn's port.
- [x] The Flask production service runs as a dedicated non-root user.
- [x] EC2 has an instance profile for CloudWatch log publishing and Secrets Manager access; secret reads are scoped to the RDS master secret and app secret, and app-secret writes are scoped to the app secret.
- [x] RDS master credentials are managed by RDS/Secrets Manager; the Flask app uses a separate application DB user whose password is stored in Secrets Manager, not Terraform state or GitHub Actions secrets.
- [x] RDS uses encrypted storage, one-day automated backups (the current Free Plan limit), and a final snapshot on destroy.
- [~] CloudWatch Agent is configured to ship app, Nginx, and bootstrap logs with seven-day retention; EC2 and RDS CPU alarms are defined. Verify log arrival and configure email notification if desired.
- [~] The deployment initializer requires access to the RDS master secret while running on the EC2 role to create the limited app user. This is scoped to the specific secret but remains an elevated capability on the host; move DB user provisioning to a separate administrative workflow for a stronger production boundary.
- [~] HTTPS bootstrap is prepared, but inactive because there is no domain yet. Configure a domain and Certbot email, point DNS to EC2, then enable and verify TLS.
- [ ] Configure an email recipient for CloudWatch alarm notifications; current alarms have no action when `alarm_notification_email` is empty.
- [ ] Review RDS deletion protection and confirm final snapshots are retained or deleted after review; snapshots and scheduled Secrets Manager deletion may continue billing.
- [ ] Add alarms for instance status, RDS storage/connections, application health, and deployment failures if the review requires broader alert coverage.
- [ ] Add dependency vulnerability scanning and a regular patch/update process.

## Part 5: Health-check code

- [x] Flask `/health` returns JSON and HTTP 200 when the configured database can run `SELECT 1`.
- [x] Flask `/health` returns JSON and HTTP 503 if the database check fails.
- [x] The deployment script checks the local health endpoint after restarting Gunicorn.
- [x] Verified the same endpoint through the public Nginx URL after infrastructure was recreated (`curl http://<EC2_PUBLIC_IP>/health` → HTTP 200, database connected).

## Part 6: AWS architecture

- [x] Terraform modules define a VPC, public subnets, security groups, one EC2 app host, and PostgreSQL RDS.
- [x] Recreate the AWS stack. App deployment and public endpoint verified (see Part 5).
- [ ] Add an Application Load Balancer if matching the assignment's full production architecture is required. It is not present and adds ongoing cost.
- [ ] Add private application subnets or otherwise document the single public EC2 as a deliberate short-lived demo compromise.
- [x] Add private database subnets.
- [ ] Add S3 only for a defined need such as versioned deployment artifacts or static assets; it is not currently used.
- [~] CloudWatch log shipping and CPU alarms are defined; configure an email recipient and add dashboards/health and storage alarms if required.
- [ ] Add Route 53 and a domain if a stable hostname and TLS certificate are required.
- [ ] Define backup retention and test restore procedures; the current one-day retention and skipped final snapshot are not a robust production recovery plan.
- [ ] Update the architecture diagram to distinguish the current budget demo from the recommended production target.

## Recommended completion order

1. Correct the assignment write-up and 502 runbook to reflect the actual Flask implementation.
2. Recreate infrastructure and verify current AWS cost, EC2 health, RDS availability, and runner status.
3. ~~Run a release-branch deployment and test order placement plus `/health` through the public URL.~~ Done — `/health` verified live; order placement smoke test still pending as an automated CI check (see Part 2).
4. Improve data safety first: private DB subnets, database backup/final snapshot policy, and recovery notes.
5. Configure a domain for HTTPS, provide the CloudWatch notification email, and verify IAM/secrets access after deployment.
6. Add migrations, PostgreSQL integration tests, and rollback.
7. Add ALB, S3, and Route 53 only if required by the review and budget; explain any deliberately omitted production components.

For a one-week demonstration on a limited credit balance, a single EC2 plus private RDS is a reasonable low-cost implementation. Describe the ALB, multi-instance, TLS/domain, monitoring, and recovery features as pending unless they are actually deployed. Check current AWS Billing and Free Tier eligibility before recreating billable resources.
