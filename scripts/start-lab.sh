#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "[1/4] Subindo PostgreSQL..."
docker compose up -d postgres

until docker compose exec -T postgres pg_isready -U zabbix -d zabbix >/dev/null 2>&1; do
  sleep 2
done

echo "[2/4] Subindo primeiro Zabbix Server para inicializar schema..."
docker compose up -d zabbix-server-01

echo "[3/4] Aguardando schema base do Zabbix ficar disponível no PostgreSQL..."
until docker compose exec -T postgres psql -U zabbix -d zabbix -tAc "select 1 from information_schema.tables where table_name='users';" 2>/dev/null | grep -q 1; do
  sleep 5
done

echo "[4/4] Subindo segundo node HA, frontend, proxy reverso e agent Linux..."
docker compose up -d zabbix-server-02 zabbix-web reverse-proxy linux-host

echo

docker compose ps

echo

echo "Acesso web: http://localhost:8080"
echo "Login padrão: Admin / zabbix"
echo "Status HA: ./scripts/ha-status.sh"
echo "Demo failover: ./scripts/failover-demo.sh"
