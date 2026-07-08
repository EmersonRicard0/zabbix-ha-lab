PAINEL VISUAL PROFISSIONAL - ZABBIX HA TOPOLOGY

Arquivos incluídos:
- docker-compose.status.yml
- start-visual-dashboard.ps1
- status-page/

Como usar:
1) Copie docker-compose.status.yml, start-visual-dashboard.ps1 e a pasta status-page para a raiz do seu lab.
2) Na pasta do lab, rode:
   .\start-visual-dashboard.ps1
3) Acesse:
   http://localhost:8090

O painel mostra:
- Reverse Proxy / NGINX
- Frontend 01 e Frontend 02
- PostgreSQL Shared DB
- Zabbix Server 01 e 02 com ACTIVE/STANDBY/UNAVAILABLE
- Host de teste linux-host-ha-demo

Atualização automática a cada 5 segundos.
