#!/usr/bin/env bash
set -euo pipefail

: "${EC2_HOST:?Set the EC2_HOST GitHub Actions secret}"
: "${EC2_SSH_KEY:?Set the EC2_SSH_KEY GitHub Actions secret}"
: "${EC2_KNOWN_HOSTS:?Set the EC2_KNOWN_HOSTS GitHub Actions secret}"
: "${DATABASE_URL:?Set the DATABASE_URL GitHub Actions secret}"

if [[ "$DATABASE_URL" == *$'\n'* || "$DATABASE_URL" == *"'"* ]]; then
  echo "DATABASE_URL must be one line and must not contain a single quote; URL-encode special characters in its password." >&2
  exit 1
fi

temporary_directory=$(mktemp -d)
trap 'rm -rf "$temporary_directory"' EXIT

private_key="$temporary_directory/ec2-key"
known_hosts="$temporary_directory/known_hosts"
printf '%s\n' "$EC2_SSH_KEY" > "$private_key"
printf '%s\n' "$EC2_KNOWN_HOSTS" > "$known_hosts"
chmod 600 "$private_key" "$known_hosts"

ssh_options=(
  -i "$private_key"
  -o IdentitiesOnly=yes
  -o StrictHostKeyChecking=yes
  -o "UserKnownHostsFile=$known_hosts"
)
remote="ubuntu@$EC2_HOST"

tar -czf - app.py requirements.txt templates static deploy/pilgrim.service |
  ssh "${ssh_options[@]}" "$remote" \
    'sudo tar --no-same-owner -xzf - -C /opt/pilgrim/app'

printf "DATABASE_URL='%s'\n" "$DATABASE_URL" |
  ssh "${ssh_options[@]}" "$remote" \
    'sudo install -d -o root -g pilgrim -m 0750 /etc/pilgrim && sudo tee /etc/pilgrim/app.env >/dev/null && sudo chown root:pilgrim /etc/pilgrim/app.env && sudo chmod 0640 /etc/pilgrim/app.env'

ssh "${ssh_options[@]}" "$remote" 'set -e
  sudo chown -R pilgrim:pilgrim /opt/pilgrim/app
  sudo install -o root -g root -m 0644 /opt/pilgrim/app/deploy/pilgrim.service /etc/systemd/system/pilgrim.service
  sudo -u pilgrim /opt/pilgrim/venv/bin/python -m pip install --disable-pip-version-check -r /opt/pilgrim/app/requirements.txt
  sudo systemctl daemon-reload
  sudo systemctl enable pilgrim
  sudo systemctl restart pilgrim
  sudo nginx -t
  sudo systemctl reload nginx
  for attempt in $(seq 1 12); do
    if curl --fail --silent http://127.0.0.1:5000/health >/dev/null; then
      exit 0
    fi
    sleep 5
  done
  sudo journalctl -u pilgrim --no-pager -n 80
  exit 1'

echo "Deployment succeeded: http://$EC2_HOST/"