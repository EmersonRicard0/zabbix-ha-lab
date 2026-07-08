import os
import time
from datetime import datetime, timezone
from typing import Any, Dict, Optional

import psycopg2
import requests
from flask import Flask, jsonify, render_template

app = Flask(__name__)

POSTGRES_HOST = os.getenv("POSTGRES_HOST", "postgres")
POSTGRES_DB = os.getenv("POSTGRES_DB", "zabbix")
POSTGRES_USER = os.getenv("POSTGRES_USER", "zabbix")
POSTGRES_PASSWORD = os.getenv("POSTGRES_PASSWORD", "zabbixpass")

ZBX_API_URL = os.getenv("ZBX_API_URL", "http://reverse-proxy/api_jsonrpc.php")
ZBX_API_USER = os.getenv("ZBX_API_USER", "Admin")
ZBX_API_PASSWORD = os.getenv("ZBX_API_PASSWORD", "zabbix")
DEMO_HOST_NAME = os.getenv("DEMO_HOST_NAME", "linux-host-ha-demo")
DEMO_ITEM_KEY = os.getenv("DEMO_ITEM_KEY", "agent.ping")

PROXY_URL = os.getenv("PROXY_URL", "http://reverse-proxy/")
WEB01_URL = os.getenv("WEB01_URL", "http://zbx-web-01:8080/")
WEB02_URL = os.getenv("WEB02_URL", "http://zbx-web-02:8080/")

STATUS_MAP = {
    0: "standby",
    1: "stopped",
    2: "unavailable",
    3: "active",
}


def check_http(url: str) -> Dict[str, Any]:
    start = time.time()
    try:
        response = requests.get(url, timeout=3, allow_redirects=True)
        latency = int((time.time() - start) * 1000)
        ok = response.status_code < 500
        return {
            "url": url,
            "ok": ok,
            "status_code": response.status_code,
            "latency_ms": latency,
            "message": "online" if ok else f"erro HTTP {response.status_code}",
        }
    except Exception as exc:
        return {
            "url": url,
            "ok": False,
            "status_code": None,
            "latency_ms": None,
            "message": str(exc),
        }


def pg_conn():
    return psycopg2.connect(
        host=POSTGRES_HOST,
        dbname=POSTGRES_DB,
        user=POSTGRES_USER,
        password=POSTGRES_PASSWORD,
    )


def get_ha_nodes() -> Dict[str, Any]:
    nodes = []
    db_ok = True
    db_error = None
    try:
        with pg_conn() as conn:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT name, address, port, status, lastaccess
                    FROM ha_node
                    ORDER BY name;
                    """
                )
                rows = cur.fetchall()
                for name, address, port, status, lastaccess in rows:
                    nodes.append(
                        {
                            "name": name,
                            "address": address,
                            "port": port,
                            "status_code": int(status),
                            "status": STATUS_MAP.get(int(status), str(status)),
                            "lastaccess_epoch": int(lastaccess) if lastaccess is not None else None,
                        }
                    )
    except Exception as exc:
        db_ok = False
        db_error = str(exc)

    active = next((n for n in nodes if n["status"] == "active"), None)
    standby = next((n for n in nodes if n["status"] == "standby"), None)

    return {
        "db_ok": db_ok,
        "db_error": db_error,
        "nodes": nodes,
        "active": active["name"] if active else None,
        "standby": standby["name"] if standby else None,
    }


def zbx_login() -> Optional[str]:
    payload = {
        "jsonrpc": "2.0",
        "method": "user.login",
        "params": {"username": ZBX_API_USER, "password": ZBX_API_PASSWORD},
        "id": 1,
    }
    response = requests.post(ZBX_API_URL, json=payload, timeout=5)
    data = response.json()
    if data.get("error"):
        raise RuntimeError(str(data["error"]))
    return data.get("result")


def zbx_call(method: str, params: Dict[str, Any], token: str):
    payload = {
        "jsonrpc": "2.0",
        "method": method,
        "params": params,
        "id": 1,
    }
    headers = {"Authorization": f"Bearer {token}"}
    response = requests.post(ZBX_API_URL, json=payload, headers=headers, timeout=5)
    data = response.json()
    if data.get("error"):
        raise RuntimeError(str(data["error"]))
    return data.get("result")


def get_demo_host_status() -> Dict[str, Any]:
    result = {
        "host_name": DEMO_HOST_NAME,
        "ok": False,
        "message": "nao consultado",
        "item_key": DEMO_ITEM_KEY,
        "lastvalue": None,
        "lastclock": None,
        "fresh": False,
        "age_seconds": None,
    }
    try:
        token = zbx_login()
        host = zbx_call(
            "host.get",
            {
                "output": ["hostid", "host", "name", "status"],
                "filter": {"host": [DEMO_HOST_NAME]},
            },
            token,
        )
        if not host:
            result["message"] = "host nao encontrado"
            return result
        hostid = host[0]["hostid"]
        item = zbx_call(
            "item.get",
            {
                "output": ["itemid", "name", "key_", "lastvalue", "lastclock", "status", "state"],
                "hostids": hostid,
                "filter": {"key_": [DEMO_ITEM_KEY]},
                "sortfield": "name",
            },
            token,
        )
        if not item:
            result["message"] = "item nao encontrado"
            return result
        item = item[0]
        lastclock = int(item.get("lastclock") or 0)
        age = int(time.time()) - lastclock if lastclock else None
        fresh = age is not None and age <= 30
        ok = item.get("lastvalue") == "1" and fresh
        result.update(
            {
                "ok": ok,
                "message": "coletando normalmente" if ok else "sem coleta recente",
                "lastvalue": item.get("lastvalue"),
                "lastclock": lastclock,
                "fresh": fresh,
                "age_seconds": age,
            }
        )
        return result
    except Exception as exc:
        result["message"] = str(exc)
        return result


def fmt_ts(epoch: Optional[int]) -> Optional[str]:
    if not epoch:
        return None
    dt = datetime.fromtimestamp(epoch, tz=timezone.utc).astimezone()
    return dt.strftime("%d/%m/%Y %H:%M:%S")


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/status")
def api_status():
    ha = get_ha_nodes()
    proxy = check_http(PROXY_URL)
    web01 = check_http(WEB01_URL)
    web02 = check_http(WEB02_URL)
    demo = get_demo_host_status()

    for node in ha["nodes"]:
        node["lastaccess"] = fmt_ts(node["lastaccess_epoch"])

    topology = {
        "updated_at": datetime.now().strftime("%d/%m/%Y %H:%M:%S"),
        "proxy": {
            "name": "Reverse Proxy / NGINX",
            "domain": "zabbix.ertechnol.com.br",
            **proxy,
        },
        "web_frontends": [
            {"name": "zbx-web-01", **web01},
            {"name": "zbx-web-02", **web02},
        ],
        "database": {
            "name": "PostgreSQL Shared DB",
            "ok": ha["db_ok"],
            "message": "conectado" if ha["db_ok"] else ha["db_error"],
            "host": POSTGRES_HOST,
        },
        "ha": ha,
        "demo_host": demo,
        "active_node": ha["active"],
    }
    return jsonify(topology)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8090, debug=False)
