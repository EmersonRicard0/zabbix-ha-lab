#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "== Runtime HA status via node 01 =="
docker compose exec -T zabbix-server-01 zabbix_server -R ha_status || true

echo

echo "== Runtime HA status via node 02 =="
docker compose exec -T zabbix-server-02 zabbix_server -R ha_status || true

echo

echo "== Últimas linhas relevantes dos logs =="
docker compose logs --tail=120 zabbix-server-01 zabbix-server-02 | grep -Ei "ha|cluster|active|standby|failover|node" || true
