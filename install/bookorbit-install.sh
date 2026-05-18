#!/usr/bin/env bash

# Copyright (c) 2021-2026 community-scripts ORG
# Author: Robin Naundorf
# License: MIT | https://github.com/senk/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/bookorbit/bookorbit

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y \
  curl \
  sudo \
  mc \
  git \
  poppler-utils \
  ffmpeg
msg_ok "Installed Dependencies"

PG_VERSION="16" PG_MODULES="pgvector" setup_postgresql
PG_DB_NAME="bookorbit" PG_DB_USER="bookorbit" PG_DB_EXTENSIONS="pg_trgm,vector" setup_postgresql_db
$STD sudo -u postgres psql -d bookorbit -c 'CREATE EXTENSION IF NOT EXISTS "uuid-ossp";'

NODE_VERSION="24" NODE_MODULE="pnpm" setup_nodejs

fetch_and_deploy_gh_release "bookorbit" "bookorbit/bookorbit" "tarball" "latest" "/opt/bookorbit-src"

msg_info "Building ${APPLICATION}"
cd /opt/bookorbit-src
$STD pnpm install --frozen-lockfile
$STD pnpm --filter server run build
$STD pnpm --filter client run build-only
msg_ok "Built ${APPLICATION}"

msg_info "Setting up ${APPLICATION}"
$STD pnpm --filter server deploy --prod --legacy /opt/bookorbit
cp -r /opt/bookorbit-src/server/dist /opt/bookorbit/dist
mkdir -p /opt/bookorbit/migrations
cp -r /opt/bookorbit-src/server/src/db/migrations/. /opt/bookorbit/migrations/
cp -r /opt/bookorbit-src/client/dist /opt/bookorbit/public
mkdir -p /opt/bookorbit/bin
cp -r /opt/bookorbit-src/server/bin/kepubify /opt/bookorbit/bin/
chmod +x /opt/bookorbit/bin/kepubify/*
mkdir -p /opt/bookorbit/data/covers /opt/bookorbit/data/book-bucket /books

JWT_SECRET=$(openssl rand -hex 32)
SETUP_BOOTSTRAP_TOKEN=$(openssl rand -hex 16)
cat <<EOF >/opt/bookorbit/.env
NODE_ENV=production
PORT=3000
APP_URL=http://${LOCAL_IP}:3000
DATABASE_URL=postgres://${PG_DB_USER}:${PG_DB_PASS}@localhost:5432/${PG_DB_NAME}
JWT_SECRET=${JWT_SECRET}
SETUP_BOOTSTRAP_TOKEN=${SETUP_BOOTSTRAP_TOKEN}
APP_DATA_PATH=/opt/bookorbit/data
EOF
{
  echo "BookOrbit Credentials"
  echo "====================="
  echo "URL: http://${LOCAL_IP}:3000"
  echo "Setup Bootstrap Token: ${SETUP_BOOTSTRAP_TOKEN}"
  echo "Database User: ${PG_DB_USER}"
  echo "Database Password: ${PG_DB_PASS}"
  echo "Database Name: ${PG_DB_NAME}"
} >~/bookorbit.creds
msg_ok "Set up ${APPLICATION}"

msg_info "Running Database Migrations"
cd /opt/bookorbit
set -a && source /opt/bookorbit/.env && set +a
$STD node dist/scripts/migrate.js
msg_ok "Ran Database Migrations"

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/bookorbit.service
[Unit]
Description=BookOrbit
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
User=root
WorkingDirectory=/opt/bookorbit
EnvironmentFile=/opt/bookorbit/.env
ExecStart=/usr/bin/node --max-old-space-size=2048 dist/main.js
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now bookorbit
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
rm -rf /opt/bookorbit-src
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
