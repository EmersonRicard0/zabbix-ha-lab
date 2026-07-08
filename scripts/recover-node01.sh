#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Subindo node 01 novamente..."
docker compose up -d zabbix-server-01

echo

echo "Status HA:"
docker compose exec -T zabbix-server-01 zabbix_server -R ha_status || true
