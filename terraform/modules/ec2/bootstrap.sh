#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates git nginx python3 python3-pip python3-venv

if ! id pilgrim >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /opt/pilgrim --shell /usr/sbin/nologin pilgrim
fi

install -d -o pilgrim -g pilgrim -m 0755 /opt/pilgrim/app /opt/pilgrim/shared
if [[ ! -x /opt/pilgrim/venv/bin/python ]]; then
  python3 -m venv /opt/pilgrim/venv
fi
chown -R pilgrim:pilgrim /opt/pilgrim

cat > /etc/nginx/sites-available/pilgrim <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;

    location / {
        proxy_pass http://127.0.0.1:${app_port};
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
NGINX

ln -sfn /etc/nginx/sites-available/pilgrim /etc/nginx/sites-enabled/pilgrim
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl enable --now nginx