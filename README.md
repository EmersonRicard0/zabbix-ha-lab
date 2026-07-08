# Lab Zabbix Server HA com Docker

Este lab sobe um ambiente leve para demonstrar HA nativo do Zabbix Server:

- 2x Zabbix Server em HA, usando o mesmo PostgreSQL
- 1x PostgreSQL Alpine
- 1x Zabbix Web Nginx
- 1x Nginx como proxy reverso na porta 8080
- 1x Linux host com Zabbix Agent 2

## Por que esse desenho?

O Zabbix HA nativo trabalha com vários servers usando o mesmo banco. Um node fica `active` e o outro fica `standby`. O frontend não deve ficar preso em um server fixo; por isso o compose do `zabbix-web` não define `ZBX_SERVER_HOST` nem `ZBX_SERVER_PORT`.

## Requisitos

- Docker
- Docker Compose v2
- Opcional: `jq` para o script de cadastro automático do host Linux

## Como subir

```bash
chmod +x scripts/*.sh
./scripts/start-lab.sh
```

Acesso:

```text
http://localhost:8080
Admin / zabbix
```

## Ver status do HA

```bash
./scripts/ha-status.sh
```

Também dá para ver pelo frontend:

```text
Reports > System information
```

## Simular failover

```bash
./scripts/failover-demo.sh
```

Depois acompanhe:

```bash
docker compose logs -f zabbix-server-02
```

Para voltar o node 01:

```bash
./scripts/recover-node01.sh
```

## Cadastrar o host Linux de teste

Opção manual pelo frontend:

```text
Data collection > Hosts > Create host
Host name: linux-host-lab
Group: Linux servers
Interface agent:
  DNS: linux-host
  Port: 10050
Template: Linux by Zabbix agent
```

Opção automática via API:

```bash
./scripts/register-linux-host.sh
```

Se o script reclamar do `jq`:

```bash
sudo apt install -y jq
```

## Testes úteis

```bash
# Containers
docker compose ps

# Logs dos servers
docker compose logs -f zabbix-server-01 zabbix-server-02

# Logs do frontend
docker compose logs -f zabbix-web reverse-proxy

# Ver portas publicadas
docker compose port zabbix-server-01 10051
docker compose port zabbix-server-02 10051
```

## Limpeza total do lab

Cuidado: remove o banco/volume do lab.

```bash
docker compose down -v
```

## Observação sobre versão

Este lab usa imagens `alpine-7.2-latest` para ficar próximo de um ambiente Zabbix 7.2. Se quiser testar versão mais nova, troque todas as ocorrências para, por exemplo, `alpine-7.4-latest` ou outra tag oficial disponível.
