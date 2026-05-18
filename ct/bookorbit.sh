#!/usr/bin/env bash
source <(curl -fsSL https://raw.githubusercontent.com/senk/ProxmoxVED/main/misc/build.func)
# Copyright (c) 2021-2026 community-scripts ORG
# Author: Robin Naundorf
# License: MIT | https://github.com/senk/ProxmoxVED/raw/main/LICENSE
# Source: https://github.com/bookorbit/bookorbit

APP="BookOrbit"
var_tags="${var_tags:-books;library}"
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2048}"
var_disk="${var_disk:-8}"
var_os="${var_os:-debian}"
var_version="${var_version:-13}"
var_unprivileged="${var_unprivileged:-1}"

header_info "$APP"
variables
color
catch_errors

function update_script() {
  header_info
  check_container_storage
  check_container_resources

  if [[ ! -d /opt/bookorbit ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi

  if check_for_gh_release "bookorbit" "bookorbit/bookorbit"; then
    msg_info "Stopping ${APP}"
    systemctl stop bookorbit
    msg_ok "Stopped ${APP}"

    msg_info "Backing up Configuration"
    cp /opt/bookorbit/.env /opt/bookorbit_env.bak
    msg_ok "Backed up Configuration"

    fetch_and_deploy_gh_release "bookorbit" "bookorbit/bookorbit" "tarball" "latest" "/opt/bookorbit-src"

    msg_info "Rebuilding ${APP}"
    cd /opt/bookorbit-src
    $STD pnpm install --frozen-lockfile
    $STD pnpm --filter server run build
    $STD pnpm --filter client run build-only
    rm -rf /opt/bookorbit/dist /opt/bookorbit/public /opt/bookorbit/migrations /opt/bookorbit/node_modules
    $STD pnpm --filter server deploy --prod --legacy /opt/bookorbit
    cp -r /opt/bookorbit-src/server/dist /opt/bookorbit/dist
    mkdir -p /opt/bookorbit/migrations
    cp -r /opt/bookorbit-src/server/src/db/migrations/. /opt/bookorbit/migrations/
    cp -r /opt/bookorbit-src/client/dist /opt/bookorbit/public
    cp -r /opt/bookorbit-src/server/bin/kepubify /opt/bookorbit/bin/
    chmod +x /opt/bookorbit/bin/kepubify/*
    msg_ok "Rebuilt ${APP}"

    msg_info "Restoring Configuration"
    cp /opt/bookorbit_env.bak /opt/bookorbit/.env
    rm -f /opt/bookorbit_env.bak
    msg_ok "Restored Configuration"

    msg_info "Running Migrations"
    cd /opt/bookorbit
    set -a && source /opt/bookorbit/.env && set +a
    $STD node dist/scripts/migrate.js
    msg_ok "Ran Migrations"

    msg_info "Cleaning Up"
    rm -rf /opt/bookorbit-src
    msg_ok "Cleaned Up"

    msg_info "Starting ${APP}"
    systemctl start bookorbit
    msg_ok "Started ${APP}"
    msg_ok "Updated successfully!"
  fi
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"
echo -e "${CREATING}${GN}${APP} setup has been successfully initialized!${CL}"
echo -e "${INFO}${YW} Access it using the following URL:${CL}"
echo -e "${TAB}${GATEWAY}${BGN}http://${IP}:3000${CL}"
echo -e "${INFO}${YW} Bootstrap token for initial setup: see ~/bookorbit.creds${CL}"
