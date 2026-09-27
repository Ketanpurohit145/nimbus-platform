#!/usr/bin/env bash
set -euo pipefail

: "${DATABASE_URL:?Set the DATABASE_URL GitHub Actions secret}"

if [[ "$DATABASE_URL" == *$'\n'* || "$DATABASE_URL" == *"'"* ]]; then
  echo "DATABASE_URL must be one line and must not contain a single quote; URL-encode special characters in its password." >&2
  exit 1
fi

tar -czf - app.py requirements.txt templates static deploy/pilgrim.service |
  sudo tar --no-same-owner -xzf - -C /opt/pilgrim/app

printf "DATABASE_URL='%s'\n" "$DATABASE_URL" |
  sudo sh -c 'install -d -o root -g pilgrim -m 0750 /etc/pilgrim && tee /etc/pilgrim/app.env >/dev/null && chown root:pilgrim /etc/pilgrim/app.env && chmod 0640 /etc/pilgrim/app.env'

sudo chown -R pilgrim:pilgrim /opt/pilgrim/app
sudo install -o root -g root -m 0644 /opt/pilgrim/app/deploy/pilgrim.service /etc/systemd/system/pilgrim.service
sudo -u pilgrim /opt/pilgrim/venv/bin/python -m pip install --disable-pip-version-check -r /opt/pilgrim/app/requirements.txt
sudo systemctl daemon-reload
sudo systemctl enable pilgrim
sudo systemctl restart pilgrim
sudo nginx -t
sudo systemctl reload nginx

for attempt in $(seq 1 12); do
  if sudo -u pilgrim /opt/pilgrim/venv/bin/python -c 'import urllib.request; urllib.request.urlopen("http://127.0.0.1:5000/health", timeout=3)' >/dev/null 2>&1; then
    echo "Deployment succeeded: http://localhost/"
    exit 0
  fi
  sleep 5
done

sudo journalctl -u pilgrim --no-pager -n 80
exit 1
