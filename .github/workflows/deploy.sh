#!/usr/bin/env bash
set -euo pipefail
# Deploys the app on the EC2 instance itself (via the self-hosted runner); no SSH access to prod is needed.

# Ship only the runtime files needed in production into /opt/pilgrim/app.
tar -czf - app.py requirements.txt templates static scripts deploy/pilgrim.service |
  sudo tar --no-same-owner -xzf - -C /opt/pilgrim/app

sudo chown -R pilgrim:pilgrim /opt/pilgrim/app
sudo install -o root -g root -m 0644 /opt/pilgrim/app/deploy/pilgrim.service /etc/systemd/system/pilgrim.service
sudo -u pilgrim /opt/pilgrim/venv/bin/python -m pip install --disable-pip-version-check -r /opt/pilgrim/app/requirements.txt
# Creates/rotates the limited-privilege app DB user; safe to re-run (no-op if credentials already exist).
sudo -u pilgrim /bin/bash -c 'set -a; source /etc/pilgrim/app.env; set +a; exec /opt/pilgrim/venv/bin/python /opt/pilgrim/app/scripts/initialize_database.py'
sudo systemctl daemon-reload
sudo systemctl enable pilgrim
sudo systemctl restart pilgrim
sudo nginx -t
sudo systemctl reload nginx

# Poll the local health endpoint until Gunicorn is ready, or fail the deploy after ~60 seconds.
for attempt in $(seq 1 12); do
  if curl --fail --silent --show-error http://127.0.0.1:5000/health >/dev/null; then
    echo "Deployment succeeded: http://localhost/"
    exit 0
  fi
  sleep 5
done

sudo journalctl -u pilgrim --no-pager -n 80
exit 1
