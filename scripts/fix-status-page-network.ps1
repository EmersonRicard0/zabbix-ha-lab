#requires -version 5
<#
  Recria o container status-page ja conectado na rede zbx_net,
  com a senha correta do Postgres.

  Rode este script a partir da RAIZ do projeto (onde estao
  docker-compose.yml e docker-compose.status.yml).
#>

Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

$ErrorActionPreference = "Stop"

function Fail($msg) {
  Write-Host "[ERRO] $msg" -ForegroundColor Red
  exit 1
}

if (-not (Test-Path "docker-compose.yml")) {
  Fail "docker-compose.yml nao encontrado. Rode este script na raiz do projeto (zabbix-ha-lab-demo-prod)."
}
if (-not (Test-Path "docker-compose.status.yml")) {
  Fail "docker-compose.status.yml nao encontrado. Rode este script na raiz do projeto (zabbix-ha-lab-demo-prod)."
}

Write-Host "[1/3] Conferindo se o lab principal esta de pe..." -ForegroundColor Cyan
docker compose ps postgres reverse-proxy zabbix-server-01 zabbix-server-02 zabbix-web-01 zabbix-web-02

Write-Host ""
Write-Host "[2/3] Recriando status-page na rede zbx_net (com --build --force-recreate)..." -ForegroundColor Cyan
docker compose -f docker-compose.yml -f docker-compose.status.yml up -d --build --force-recreate status-page
if ($LASTEXITCODE -ne 0) {
  Fail "Falha ao subir o status-page. Veja o log acima."
}

Write-Host ""
Write-Host "[3/3] Conferindo se o container enxerga os outros servicos..." -ForegroundColor Cyan
Start-Sleep -Seconds 3
docker exec zbx-ha-topology sh -c "getent hosts reverse-proxy postgres zbx-web-01 zbx-web-02 2>/dev/null || echo 'DNS ainda nao resolveu -- confira docker compose logs status-page'"

Write-Host ""
Write-Host "[OK] Painel disponivel em http://localhost:8090" -ForegroundColor Green
Write-Host "Se algum hostname acima nao apareceu, rode: docker compose logs status-page" -ForegroundColor Yellow
