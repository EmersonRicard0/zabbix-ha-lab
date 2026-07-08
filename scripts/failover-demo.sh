#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "Parando o node 01 para simular falha..."
docker compose stop zabbix-server-01

echo

echo "Status pelo node 02:"
docker compose exec -T zabbix-server-02 zabbix_server -R ha_status || true

echo

echo "Acompanhe o failover nos logs:"
echo "docker compose logs -f zabbix-server-02"
echo

echo "Para voltar o node 01: ./scripts/recover-node01.sh"
