#!/usr/bin/env bash
# Recria o container status-page ja conectado na rede zbx_net,
# com a senha correta do Postgres.
#
# Rode este script a partir da RAIZ do projeto (onde estao
# docker-compose.yml e docker-compose.status.yml).

set -euo pipefail

if [ ! -f "docker-compose.yml" ] || [ ! -f "docker-compose.status.yml" ]; then
  echo "[ERRO] docker-compose.yml / docker-compose.status.yml nao encontrados."
  echo "       Rode este script na raiz do projeto (zabbix-ha-lab-demo-prod)."
  exit 1
fi

echo "[1/3] Conferindo se o lab principal esta de pe..."
docker compose ps postgres reverse-proxy zabbix-server-01 zabbix-server-02 zabbix-web-01 zabbix-web-02

echo
echo "[2/3] Recriando status-page na rede zbx_net (com --build --force-recreate)..."
docker compose -f docker-compose.yml -f docker-compose.status.yml up -d --build --force-recreate status-page

echo
echo "[3/3] Conferindo se o container enxerga os outros servicos..."
sleep 3
docker exec zbx-ha-topology sh -c \
  "getent hosts reverse-proxy postgres zbx-web-01 zbx-web-02 2>/dev/null || echo 'DNS ainda nao resolveu -- confira: docker compose logs status-page'"

echo
echo "[OK] Painel disponivel em http://localhost:8090"
echo "Se algum hostname nao apareceu acima, rode: docker compose logs status-page"
