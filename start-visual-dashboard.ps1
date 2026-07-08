Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
Write-Host "[INFO] Subindo painel visual de topologia do Zabbix HA..." -ForegroundColor Cyan
docker compose -f docker-compose.yml -f docker-compose.status.yml up -d --build status-page
Write-Host "[OK] Painel disponivel em http://localhost:8090" -ForegroundColor Green
