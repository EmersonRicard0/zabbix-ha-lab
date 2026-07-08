#!/usr/bin/env bash
set -euo pipefail

ZBX_URL="${ZBX_URL:-http://localhost:8080/api_jsonrpc.php}"
ZBX_USER="${ZBX_USER:-Admin}"
ZBX_PASS="${ZBX_PASS:-zabbix}"
HOST_NAME="${HOST_NAME:-linux-host-lab}"
HOST_DNS="${HOST_DNS:-linux-host}"

if ! command -v jq >/dev/null 2>&1; then
  echo "Este script precisa do jq instalado no host. Ex.: sudo apt install -y jq"
  exit 1
fi

api() {
  local payload="$1"
  curl -sS -H 'Content-Type: application/json-rpc' -d "$payload" "$ZBX_URL"
}

echo "Autenticando na API do Zabbix..."
AUTH=$(api "{\"jsonrpc\":\"2.0\",\"method\":\"user.login\",\"params\":{\"username\":\"$ZBX_USER\",\"password\":\"$ZBX_PASS\"},\"id\":1}" | jq -r '.result // empty')

if [ -z "$AUTH" ] || [ "$AUTH" = "null" ]; then
  echo "Falha ao autenticar. Confere URL/login/senha e se o frontend já abriu."
  exit 1
fi

GROUP_ID=$(api "{\"jsonrpc\":\"2.0\",\"method\":\"hostgroup.get\",\"params\":{\"filter\":{\"name\":[\"Linux servers\"]}},\"auth\":\"$AUTH\",\"id\":2}" | jq -r '.result[0].groupid // empty')
TEMPLATE_ID=$(api "{\"jsonrpc\":\"2.0\",\"method\":\"template.get\",\"params\":{\"search\":{\"host\":\"Linux by Zabbix agent\"},\"output\":[\"templateid\",\"host\"]},\"auth\":\"$AUTH\",\"id\":3}" | jq -r '.result[0].templateid // empty')

if [ -z "$GROUP_ID" ] || [ -z "$TEMPLATE_ID" ]; then
  echo "Não encontrei grupo 'Linux servers' ou template 'Linux by Zabbix agent'. Crie o host manualmente pelo frontend."
  exit 1
fi

EXISTS=$(api "{\"jsonrpc\":\"2.0\",\"method\":\"host.get\",\"params\":{\"filter\":{\"host\":[\"$HOST_NAME\"]}},\"auth\":\"$AUTH\",\"id\":4}" | jq -r '.result[0].hostid // empty')

if [ -n "$EXISTS" ]; then
  echo "Host '$HOST_NAME' já existe. hostid=$EXISTS"
  exit 0
fi

PAYLOAD=$(cat <<JSON
{
  "jsonrpc": "2.0",
  "method": "host.create",
  "params": {
    "host": "$HOST_NAME",
    "interfaces": [
      {
        "type": 1,
        "main": 1,
        "useip": 0,
        "ip": "",
        "dns": "$HOST_DNS",
        "port": "10050"
      }
    ],
    "groups": [{"groupid": "$GROUP_ID"}],
    "templates": [{"templateid": "$TEMPLATE_ID"}]
  },
  "auth": "$AUTH",
  "id": 5
}
JSON
)

api "$PAYLOAD" | jq .

echo "Host '$HOST_NAME' criado apontando para DNS '$HOST_DNS:10050'."
