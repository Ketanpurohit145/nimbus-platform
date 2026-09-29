#!/bin/bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y ca-certificates certbot curl git nginx openssl python3 python3-certbot-nginx python3-pip python3-venv
curl -fsSLo /etc/ssl/certs/rds-global-bundle.pem \
  https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem
chmod 0644 /etc/ssl/certs/rds-global-bundle.pem

if ! id pilgrim >/dev/null 2>&1; then
  useradd --system --create-home --home-dir /opt/pilgrim --shell /usr/sbin/nologin pilgrim
fi

install -d -o pilgrim -g pilgrim -m 0755 /opt/pilgrim/app /opt/pilgrim/shared
install -d -o pilgrim -g pilgrim -m 0750 /var/log/pilgrim
touch /var/log/pilgrim/app.log /var/log/pilgrim/app-error.log
chown pilgrim:pilgrim /var/log/pilgrim/app.log /var/log/pilgrim/app-error.log
if [[ ! -x /opt/pilgrim/venv/bin/python ]]; then
  python3 -m venv /opt/pilgrim/venv
fi
chown -R pilgrim:pilgrim /opt/pilgrim

install -d -o root -g pilgrim -m 0750 /etc/pilgrim
printf 'AWS_REGION=%s\nDATABASE_NAME=%s\nDB_ADMIN_SECRET_ARN=%s\nDB_APP_SECRET_ARN=%s\nSECRET_KEY=%s\n' \
  '${aws_region}' '${db_name}' '${db_admin_secret_arn}' '${db_app_secret_arn}' "$(openssl rand -hex 32)" \
  > /etc/pilgrim/app.env
chown root:pilgrim /etc/pilgrim/app.env
chmod 0640 /etc/pilgrim/app.env

cat > /etc/nginx/sites-available/pilgrim <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name ${nginx_server_name};

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

DOMAIN_NAME=${domain_name_json}
CERTBOT_EMAIL=${certbot_email_json}
if [[ -n "$DOMAIN_NAME" && -n "$CERTBOT_EMAIL" ]]; then
  certbot --nginx --non-interactive --agree-tos --redirect \
    --email "$CERTBOT_EMAIL" -d "$DOMAIN_NAME"
  systemctl enable --now certbot.timer
fi

curl -fsSLo /tmp/amazon-cloudwatch-agent.deb \
  https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb
dpkg -i -E /tmp/amazon-cloudwatch-agent.deb
install -d -o root -g root -m 0755 /opt/aws/amazon-cloudwatch-agent/etc
cat > /opt/aws/amazon-cloudwatch-agent/etc/pilgrim.json <<'CWAGENT'
{
  "agent": {
    "region": "${aws_region}",
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/nginx/access.log",
            "log_group_name": "${log_group_names.nginx_access}",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/nginx/error.log",
            "log_group_name": "${log_group_names.nginx_error}",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/pilgrim/app.log",
            "log_group_name": "${log_group_names.app}",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/pilgrim/app-error.log",
            "log_group_name": "${log_group_names.app_error}",
            "log_stream_name": "{instance_id}"
          },
          {
            "file_path": "/var/log/cloud-init-output.log",
            "log_group_name": "${log_group_names.bootstrap}",
            "log_stream_name": "{instance_id}"
          }
        ]
      }
    }
  }
}
CWAGENT
chmod 0644 /opt/aws/amazon-cloudwatch-agent/etc/pilgrim.json
/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 -c file:/opt/aws/amazon-cloudwatch-agent/etc/pilgrim.json -s