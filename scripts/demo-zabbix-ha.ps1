<#
.SYNOPSIS
  Prepara e opera o lab Zabbix HA para apresentação em Windows/PowerShell.

.USAGE
  # Aplicar compose com IPs fake-prod, recriar do zero e registrar host de demo
  .\demo-zabbix-ha.ps1 -Action setup -Reset

  # Ver status HA
  .\demo-zabbix-ha.ps1 -Action status

  # Consultar tabela ha_node no PostgreSQL
  .\demo-zabbix-ha.ps1 -Action query-db

  # Parar automaticamente o node ACTIVE para demonstrar failover
  .\demo-zabbix-ha.ps1 -Action failover

  # Subir os dois nodes novamente
  .\demo-zabbix-ha.ps1 -Action recover

  # Registrar/recriar host de monitoramento
  .\demo-zabbix-ha.ps1 -Action register-host

  # Ajustar failover delay
  .\demo-zabbix-ha.ps1 -Action set-delay -Delay 10s
#>

param(
    [ValidateSet('setup','status','query-db','failover','recover','register-host','set-delay','down')]
    [string]$Action = 'setup',

    [switch]$Reset,

    [string]$Delay = '10s'
)

$ErrorActionPreference = 'Stop'

function Write-Info($msg) {
    Write-Host "[INFO] $msg" -ForegroundColor Cyan
}

function Write-Ok($msg) {
    Write-Host "[OK] $msg" -ForegroundColor Green
}

function Write-Warn($msg) {
    Write-Host "[WARN] $msg" -ForegroundColor Yellow
}

function Assert-InLabFolder {
    if (-not (Test-Path '.\docker-compose.yml')) {
        throw "Execute este script dentro da pasta do lab, onde fica o docker-compose.yml."
    }
    if (-not (Test-Path '.\nginx')) {
        New-Item -ItemType Directory -Path '.\nginx' | Out-Null
    }
}

function Write-DemoFiles {
    Assert-InLabFolder

    $compose = @'
name: zabbix-ha-lab

services:
  postgres:
    image: postgres:16-alpine
    container_name: zbx-ha-postgres
    environment:
      POSTGRES_DB: zabbix
      POSTGRES_USER: zabbix
      POSTGRES_PASSWORD: zabbix_pwd
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - pgdata:/var/lib/postgresql/data
    networks:
      zbx_net:
        ipv4_address: 192.168.253.12
        aliases:
          - postgres
          - db-zabbix
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U zabbix -d zabbix"]
      interval: 10s
      timeout: 5s
      retries: 10
    restart: unless-stopped
    mem_limit: 512m

  zabbix-server-01:
    image: zabbix/zabbix-server-pgsql:alpine-7.2-latest
    container_name: zbx-server-01
    hostname: zbx-node-01
    environment:
      DB_SERVER_HOST: 192.168.253.12
      POSTGRES_DB: zabbix
      POSTGRES_USER: zabbix
      POSTGRES_PASSWORD: zabbix_pwd
      ZBX_HANODENAME: zbx-node-01
      ZBX_NODEADDRESS: 192.168.253.9:10051
      ZBX_STARTPOLLERS: 5
      ZBX_STARTPINGERS: 2
      ZBX_STARTSNMPPOLLERS: 1
      ZBX_STARTDBSYNCERS: 2
      ZBX_STARTPREPROCESSORS: 2
      ZBX_CACHESIZE: 64M
      ZBX_HISTORYCACHESIZE: 16M
      ZBX_HISTORYINDEXCACHESIZE: 4M
      ZBX_TRENDCACHESIZE: 4M
      ZBX_TRENDFUNCTIONCACHESIZE: 4M
      ZBX_VALUECACHESIZE: 32M
      ZBX_TIMEOUT: 5
    ports:
      - "11051:10051"
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      zbx_net:
        ipv4_address: 192.168.253.9
        aliases:
          - zbx-node-01
          - zabbix-server-01
    restart: unless-stopped
    mem_limit: 384m

  zabbix-server-02:
    image: zabbix/zabbix-server-pgsql:alpine-7.2-latest
    container_name: zbx-server-02
    hostname: zbx-node-02
    environment:
      DB_SERVER_HOST: 192.168.253.12
      POSTGRES_DB: zabbix
      POSTGRES_USER: zabbix
      POSTGRES_PASSWORD: zabbix_pwd
      ZBX_HANODENAME: zbx-node-02
      ZBX_NODEADDRESS: 192.168.254.9:10051
      ZBX_STARTPOLLERS: 5
      ZBX_STARTPINGERS: 2
      ZBX_STARTSNMPPOLLERS: 1
      ZBX_STARTDBSYNCERS: 2
      ZBX_STARTPREPROCESSORS: 2
      ZBX_CACHESIZE: 64M
      ZBX_HISTORYCACHESIZE: 16M
      ZBX_HISTORYINDEXCACHESIZE: 4M
      ZBX_TRENDCACHESIZE: 4M
      ZBX_TRENDFUNCTIONCACHESIZE: 4M
      ZBX_VALUECACHESIZE: 32M
      ZBX_TIMEOUT: 5
    ports:
      - "11052:10051"
    depends_on:
      postgres:
        condition: service_healthy
      zabbix-server-01:
        condition: service_started
    networks:
      zbx_net:
        ipv4_address: 192.168.254.9
        aliases:
          - zbx-node-02
          - zabbix-server-02
    restart: unless-stopped
    mem_limit: 384m

  zabbix-web-01:
    image: zabbix/zabbix-web-nginx-pgsql:alpine-7.2-latest
    container_name: zbx-web-01
    hostname: zbx-web-01
    environment:
      DB_SERVER_HOST: 192.168.253.12
      POSTGRES_DB: zabbix
      POSTGRES_USER: zabbix
      POSTGRES_PASSWORD: zabbix_pwd
      PHP_TZ: America/Fortaleza
      ZBX_SERVER_NAME: monitoramento.networksecure.com.br
      ZBX_MEMORYLIMIT: 128M
      ZBX_POSTMAXSIZE: 16M
      ZBX_UPLOADMAXFILESIZE: 2M
    depends_on:
      postgres:
        condition: service_healthy
      zabbix-server-01:
        condition: service_started
      zabbix-server-02:
        condition: service_started
    networks:
      zbx_net:
        ipv4_address: 192.168.253.20
        aliases:
          - zabbix-web-01
    expose:
      - "8080"
    restart: unless-stopped
    mem_limit: 256m

  zabbix-web-02:
    image: zabbix/zabbix-web-nginx-pgsql:alpine-7.2-latest
    container_name: zbx-web-02
    hostname: zbx-web-02
    environment:
      DB_SERVER_HOST: 192.168.253.12
      POSTGRES_DB: zabbix
      POSTGRES_USER: zabbix
      POSTGRES_PASSWORD: zabbix_pwd
      PHP_TZ: America/Fortaleza
      ZBX_SERVER_NAME: monitoramento.networksecure.com.br
      ZBX_MEMORYLIMIT: 128M
      ZBX_POSTMAXSIZE: 16M
      ZBX_UPLOADMAXFILESIZE: 2M
    depends_on:
      postgres:
        condition: service_healthy
      zabbix-server-01:
        condition: service_started
      zabbix-server-02:
        condition: service_started
    networks:
      zbx_net:
        ipv4_address: 192.168.254.20
        aliases:
          - zabbix-web-02
    expose:
      - "8080"
    restart: unless-stopped
    mem_limit: 256m

  reverse-proxy:
    image: nginx:alpine
    container_name: zbx-reverse-proxy
    hostname: reverse-proxy
    ports:
      - "8080:80"
    volumes:
      - ./nginx/default.conf:/etc/nginx/conf.d/default.conf:ro
    depends_on:
      - zabbix-web-01
      - zabbix-web-02
    networks:
      zbx_net:
        ipv4_address: 192.168.253.5
        aliases:
          - monitoramento.networksecure.com.br
          - reverse-proxy
    restart: unless-stopped
    mem_limit: 64m

  linux-host:
    image: zabbix/zabbix-agent2:alpine-7.2-latest
    container_name: linux-host-lab
    hostname: linux-host-ha-demo
    environment:
      ZBX_HOSTNAME: linux-host-ha-demo
      ZBX_SERVER_HOST: 192.168.253.9,192.168.254.9
      ZBX_SERVER_ACTIVE: 192.168.253.9;192.168.254.9
      ZBX_ACTIVE_ALLOW: "true"
      ZBX_PASSIVE_ALLOW: "true"
    depends_on:
      - zabbix-server-01
      - zabbix-server-02
    networks:
      zbx_net:
        ipv4_address: 192.168.254.100
        aliases:
          - linux-host
          - linux-host-lab
          - linux-host-ha-demo
    restart: unless-stopped
    mem_limit: 128m

networks:
  zbx_net:
    driver: bridge
    ipam:
      config:
        - subnet: 192.168.252.0/22
          gateway: 192.168.252.1

volumes:
  pgdata:
'@

    $nginx = @'
upstream zabbix_web_backend {
    server 192.168.253.20:8080 max_fails=3 fail_timeout=10s;
    server 192.168.254.20:8080 max_fails=3 fail_timeout=10s;
}

server {
    listen 80;
    server_name monitoramento.networksecure.com.br _;

    access_log /var/log/nginx/access.log;
    error_log  /var/log/nginx/error.log warn;

    location / {
        proxy_pass http://zabbix_web_backend;
        proxy_http_version 1.1;

        proxy_set_header Host monitoramento.networksecure.com.br;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto http;

        proxy_read_timeout 300;
        proxy_connect_timeout 60;
        proxy_send_timeout 300;
    }
}
'@

    Copy-Item '.\docker-compose.yml' ".\docker-compose.backup.$((Get-Date).ToString('yyyyMMdd-HHmmss')).yml" -ErrorAction SilentlyContinue
    Set-Content -Path '.\docker-compose.yml' -Value $compose -Encoding UTF8
    Set-Content -Path '.\nginx\default.conf' -Value $nginx -Encoding UTF8
    Write-Ok 'docker-compose.yml e nginx/default.conf atualizados para o cenário fake-prod.'
}

function Wait-DbSchema {
    Write-Info 'Aguardando schema do Zabbix ser criado no PostgreSQL...'
    for ($i = 1; $i -le 90; $i++) {
        try {
            $result = docker exec zbx-ha-postgres psql -U zabbix -d zabbix -tAc "select count(*) from information_schema.tables where table_schema='public' and table_name='config';" 2>$null
            if (($result -join '').Trim() -eq '1') {
                Write-Ok 'Schema do Zabbix encontrado.'
                return
            }
        } catch {}
        Start-Sleep -Seconds 2
    }
    throw 'Timeout aguardando o schema do Zabbix. Confira: docker compose logs zabbix-server-01'
}

function Invoke-ZabbixApi {
    param(
        [string]$Method,
        [object]$Params,
        [string]$AuthToken = $null
    )

    $body = [ordered]@{
        jsonrpc = '2.0'
        method  = $Method
        params  = $Params
        id      = 1
    }

    if ($AuthToken) {
        $body.auth = $AuthToken
    }

    $json = $body | ConvertTo-Json -Depth 30
    $response = Invoke-RestMethod -Uri 'http://localhost:8080/api_jsonrpc.php' -Method Post -ContentType 'application/json-rpc' -Body $json -TimeoutSec 10

    if ($response.error) {
        $err = $response.error | ConvertTo-Json -Depth 10
        throw "Erro na API Zabbix metodo $Method: $err"
    }

    return $response.result
}

function Wait-ZabbixApi {
    Write-Info 'Aguardando API do Zabbix responder em http://localhost:8080 ...'
    for ($i = 1; $i -le 90; $i++) {
        try {
            $token = Invoke-ZabbixApi -Method 'user.login' -Params @{ username = 'Admin'; password = 'zabbix' }
            if ($token) {
                Write-Ok 'API do Zabbix respondeu.'
                return $token
            }
        } catch {}
        Start-Sleep -Seconds 2
    }
    throw 'Timeout aguardando API do Zabbix. Tente abrir http://localhost:8080 e confira os logs do zabbix-web.'
}

function Register-DemoHost {
    $token = Wait-ZabbixApi

    Write-Info 'Criando/validando grupo Linux servers...'
    $groups = Invoke-ZabbixApi -Method 'hostgroup.get' -Params @{ output = @('groupid','name'); filter = @{ name = @('Linux servers') } } -AuthToken $token
    if ($groups.Count -gt 0) {
        $groupId = $groups[0].groupid
    } else {
        $createdGroup = Invoke-ZabbixApi -Method 'hostgroup.create' -Params @{ name = 'Linux servers' } -AuthToken $token
        $groupId = $createdGroup.groupids[0]
    }

    $hostName = 'linux-host-ha-demo'
    $visibleName = 'Linux Host HA Demo - 192.168.254.100'

    $existing = Invoke-ZabbixApi -Method 'host.get' -Params @{ output = @('hostid','host'); selectInterfaces = @('interfaceid','ip','dns','port'); filter = @{ host = @($hostName) } } -AuthToken $token

    if ($existing.Count -gt 0) {
        $hostId = $existing[0].hostid
        $interfaceId = $existing[0].interfaces[0].interfaceid
        Write-Ok "Host $hostName ja existe. hostid=$hostId"
    } else {
        Write-Info 'Criando host monitorado da demo...'
        $createdHost = Invoke-ZabbixApi -Method 'host.create' -Params @{
            host = $hostName
            name = $visibleName
            groups = @(@{ groupid = $groupId })
            interfaces = @(@{
                type = 1
                main = 1
                useip = 1
                ip = '192.168.254.100'
                dns = ''
                port = '10050'
            })
        } -AuthToken $token
        $hostId = $createdHost.hostids[0]
        $hostData = Invoke-ZabbixApi -Method 'host.get' -Params @{ output = @('hostid'); selectInterfaces = @('interfaceid'); hostids = @($hostId) } -AuthToken $token
        $interfaceId = $hostData[0].interfaces[0].interfaceid
        Write-Ok "Host criado. hostid=$hostId"
    }

    $items = Invoke-ZabbixApi -Method 'item.get' -Params @{ output = @('itemid','name','key_'); hostids = @($hostId); filter = @{ key_ = @('agent.ping') } } -AuthToken $token
    if ($items.Count -eq 0) {
        Write-Info 'Criando item HA Demo - Agent Ping com intervalo de 5s...'
        Invoke-ZabbixApi -Method 'item.create' -Params @{
            name = 'HA Demo - Agent Ping'
            key_ = 'agent.ping'
            hostid = $hostId
            type = 0
            value_type = 3
            delay = '5s'
            interfaceid = $interfaceId
        } -AuthToken $token | Out-Null
        Write-Ok 'Item agent.ping criado.'
    } else {
        Write-Ok 'Item agent.ping ja existe.'
    }

    Write-Ok 'Host de monitoramento pronto para a demo.'
    Write-Host ''
    Write-Host 'Abra no Zabbix:' -ForegroundColor Cyan
    Write-Host 'Monitoring > Latest data > Host: Linux Host HA Demo - 192.168.254.100'
}

function Invoke-HaStatus {
    Write-Info 'Tentando ha_status no node 01...'
    $out1 = docker compose exec -T zabbix-server-01 zabbix_server -R ha_status 2>&1
    if ($LASTEXITCODE -eq 0) {
        $out1
        return
    }

    Write-Warn ($out1 -join "`n")
    Write-Info 'Tentando ha_status no node 02...'
    $out2 = docker compose exec -T zabbix-server-02 zabbix_server -R ha_status 2>&1
    if ($LASTEXITCODE -eq 0) {
        $out2
        return
    }

    $out2
}

function Query-HaDb {
    docker compose exec -T postgres psql -U zabbix -d zabbix -c "select name,address,port,case status when 0 then 'standby' when 1 then 'stopped manually' when 2 then 'unavailable' when 3 then 'active' else status::text end as status,to_timestamp(lastaccess) at time zone 'America/Fortaleza' as lastaccess_brt from ha_node order by name;"
}

function Set-FailoverDelay {
    param([string]$NewDelay)
    Write-Info "Ajustando failover delay para $NewDelay no node ativo..."

    $out1 = docker compose exec -T zabbix-server-01 zabbix_server -R "ha_set_failover_delay=$NewDelay" 2>&1
    if ($LASTEXITCODE -eq 0) {
        $out1
        Write-Ok "Failover delay ajustado para $NewDelay pelo node 01."
        return
    }

    $out2 = docker compose exec -T zabbix-server-02 zabbix_server -R "ha_set_failover_delay=$NewDelay" 2>&1
    if ($LASTEXITCODE -eq 0) {
        $out2
        Write-Ok "Failover delay ajustado para $NewDelay pelo node 02."
        return
    }

    Write-Warn 'Nao foi possivel ajustar o delay. Confira se ha algum node ACTIVE.'
    Write-Warn ($out1 -join "`n")
    Write-Warn ($out2 -join "`n")
}

function Get-ActiveNodeName {
    try {
        $active = docker compose exec -T postgres psql -U zabbix -d zabbix -tAc "select name from ha_node where status=3 limit 1;" 2>$null
        return (($active -join '').Trim())
    } catch {
        return $null
    }
}

function Stop-ActiveNode {
    $active = Get-ActiveNodeName
    if (-not $active) {
        throw 'Nao consegui identificar o node ativo pela tabela ha_node.'
    }

    if ($active -eq 'zbx-node-01') {
        Write-Info 'Node ativo atual: zbx-node-01. Parando zabbix-server-01...'
        docker compose stop zabbix-server-01
    } elseif ($active -eq 'zbx-node-02') {
        Write-Info 'Node ativo atual: zbx-node-02. Parando zabbix-server-02...'
        docker compose stop zabbix-server-02
    } else {
        throw "Node ativo desconhecido: $active"
    }

    Write-Ok 'Node ativo parado. Agora aguarde o failover delay e rode: .\demo-zabbix-ha.ps1 -Action status'
}

function Recover-All {
    Write-Info 'Subindo os dois Zabbix Servers...'
    docker compose start zabbix-server-01 zabbix-server-02
    Start-Sleep -Seconds 5
    Invoke-HaStatus
}

function Setup-Lab {
    Write-DemoFiles

    if ($Reset) {
        Write-Warn 'Reset habilitado: derrubando containers e apagando volume do PostgreSQL.'
        docker compose down -v
    } else {
        Write-Info 'Derrubando containers para recriar a rede com os IPs fake-prod, preservando volume do PostgreSQL.'
        docker compose down
    }

    Write-Info 'Subindo PostgreSQL...'
    docker compose up -d postgres

    Write-Info 'Subindo Zabbix Server 01 primeiro para inicializar o banco de forma controlada...'
    docker compose up -d zabbix-server-01

    Wait-DbSchema

    Write-Info 'Subindo node 02, frontends, proxy reverso e host monitorado...'
    docker compose up -d zabbix-server-02 zabbix-web-01 zabbix-web-02 reverse-proxy linux-host

    Start-Sleep -Seconds 10
    Set-FailoverDelay -NewDelay $Delay
    Register-DemoHost

    Write-Host ''
    Write-Ok 'Lab fake-prod pronto.'
    Write-Host 'URL: http://localhost:8080' -ForegroundColor Cyan
    Write-Host 'Usuario: Admin' -ForegroundColor Cyan
    Write-Host 'Senha: zabbix' -ForegroundColor Cyan
    Write-Host ''
    Write-Host 'Comandos uteis:' -ForegroundColor Cyan
    Write-Host '.\demo-zabbix-ha.ps1 -Action status'
    Write-Host '.\demo-zabbix-ha.ps1 -Action query-db'
    Write-Host '.\demo-zabbix-ha.ps1 -Action failover'
    Write-Host '.\demo-zabbix-ha.ps1 -Action recover'
}

Assert-InLabFolder

switch ($Action) {
    'setup'         { Setup-Lab }
    'status'        { Invoke-HaStatus }
    'query-db'      { Query-HaDb }
    'failover'      { Stop-ActiveNode }
    'recover'       { Recover-All }
    'register-host' { Register-DemoHost }
    'set-delay'     { Set-FailoverDelay -NewDelay $Delay }
    'down'          { docker compose down }
}
