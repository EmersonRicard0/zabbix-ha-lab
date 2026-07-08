const CANVAS_W = 1100;

let lastKnownActive = null;
let bannerTimer = null;
let eventFlashTimer = null;

async function fetchStatus() {
  const response = await fetch('/api/status');
  if (!response.ok) throw new Error('Falha ao consultar status');
  return response.json();
}

function setText(id, text) {
  const el = document.getElementById(id);
  if (!el) return;
  el.textContent = text;
  el.title = text;
}

function shortMsg(text, max = 90) {
  if (!text) return '--';
  const clean = String(text).replace(/\s+/g, ' ').trim();
  return clean.length > max ? `${clean.slice(0, max)}…` : clean;
}

function badgeClass(status) {
  if (status === 'active') return 'badge badge-active';
  if (status === 'standby') return 'badge badge-standby';
  if (status === 'unavailable' || status === 'stopped' || status === 'unknown' || !status) return 'badge badge-unavailable';
  return 'badge badge-neutral';
}

/* ---------- Canvas scaling ---------- */
function scaleCanvas() {
  const viewport = document.getElementById('topoViewport');
  const canvas = document.getElementById('topoCanvas');
  if (!viewport || !canvas) return;
  const w = viewport.clientWidth;
  if (w < 720) return; // fallback list takes over via CSS media query
  let scale = w / CANVAS_W;
  if (scale > 1.15) scale = 1.15;
  if (scale < 0.42) scale = 0.42;
  canvas.style.transform = `scale(${scale})`;
  viewport.style.height = `${1000 * scale}px`;
}

/* ---------- Link / node state helpers ---------- */
function setLinkState(linkId, dotId, breakId, state) {
  const link = document.getElementById(linkId);
  const dot = dotId ? document.getElementById(dotId) : null;
  const brk = breakId ? document.getElementById(breakId) : null;

  if (link) {
    link.classList.remove('state-flow', 'state-idle', 'state-down');
    link.classList.add(`state-${state}`);
  }
  if (dot) {
    dot.classList.remove('state-flow');
    if (state === 'flow') dot.classList.add('state-flow');
  }
  if (brk) {
    brk.classList.toggle('show', state === 'down');
  }
}

function setNodeRole(nodeId, role) {
  const el = document.getElementById(nodeId);
  if (!el) return;
  el.classList.remove('role-active', 'role-standby', 'role-down', 'ok', 'bad');
  if (role === 'active') el.classList.add('role-active');
  else if (role === 'standby') el.classList.add('role-standby');
  else if (role === 'down') el.classList.add('role-down');
}

function setNodeOk(nodeId, ok) {
  const el = document.getElementById(nodeId);
  if (!el) return;
  el.classList.remove('ok', 'bad');
  el.classList.add(ok ? 'ok' : 'bad');
}

function setRoleFlag(flagId, status) {
  const el = document.getElementById(flagId);
  if (!el) return;
  el.classList.remove('flag-active', 'flag-standby', 'flag-down');
  if (status === 'active') { el.classList.add('flag-active'); el.textContent = 'ACTIVE'; }
  else if (status === 'standby') { el.classList.add('flag-standby'); el.textContent = 'STANDBY'; }
  else if (status === 'unavailable' || status === 'stopped') { el.classList.add('flag-down'); el.textContent = 'DOWN'; }
  else { el.classList.add('flag-down'); el.textContent = 'SEM DADOS'; }
}

/* ---------- Failover banner + last-event line ---------- */
function showFailoverBanner(from, to) {
  const banner = document.getElementById('failoverBanner');
  if (!banner) return;
  banner.textContent = `⚡ FAILOVER DETECTADO — ${from} caiu, ${to} assumiu a coleta`;
  banner.classList.add('show');
  clearTimeout(bannerTimer);
  bannerTimer = setTimeout(() => banner.classList.remove('show'), 8000);
}

function updateLastEvent(from, to) {
  const el = document.getElementById('lastEventLine');
  if (!el) return;
  const now = new Date().toLocaleTimeString('pt-BR');
  el.textContent = `Último failover: ${from} → ${to} às ${now}`;
  el.classList.add('flash');
  clearTimeout(eventFlashTimer);
  eventFlashTimer = setTimeout(() => el.classList.remove('flash'), 2500);
}

function showConnectivityAlert(message) {
  const el = document.getElementById('connectivityAlert');
  if (!el) return;
  if (!message) {
    el.style.display = 'none';
    el.textContent = '';
    return;
  }
  el.textContent = message;
  el.style.display = 'flex';
}

/* ---------- Fallback (mobile) ---------- */
function renderFallback(data, srv01, srv02) {
  const el = document.getElementById('fallbackList');
  if (!el) return;
  const srv01Ok = srv01.status === 'active' || srv01.status === 'standby';
  const srv02Ok = srv02.status === 'active' || srv02.status === 'standby';
  const rows = [
    ['Reverse Proxy', data.proxy.message, data.proxy.ok],
    ['Frontend 01', data.web_frontends[0].message, data.web_frontends[0].ok],
    ['Frontend 02', data.web_frontends[1].message, data.web_frontends[1].ok],
    ['PostgreSQL', data.database.message, data.database.ok],
    [`Zabbix Server 01 — ${(srv01.status || 'sem dados').toUpperCase()}`, srv01.lastaccess || '--', srv01Ok],
    [`Zabbix Server 02 — ${(srv02.status || 'sem dados').toUpperCase()}`, srv02.lastaccess || '--', srv02Ok],
    ['Host de teste', data.demo_host.message, data.demo_host.ok],
  ];
  el.innerHTML = rows.map(([name, meta, ok]) => `
    <div class="fallback-item">
      <div>
        <div class="fi-name">${name}</div>
        <div class="fi-meta" title="${(meta || '--').replace(/"/g, '&quot;')}">${shortMsg(meta, 46)}</div>
      </div>
      <span class="status-dot ${ok ? 'dot-good' : 'dot-bad'}"></span>
    </div>
  `).join('');
}

/* ---------- Main refresh ---------- */
async function refresh() {
  try {
    const data = await fetchStatus();

    setText('updatedAt', data.updated_at || '--');
    const activeBadge = document.getElementById('activeNodeBadge');
    if (activeBadge) {
      activeBadge.className = badgeClass(data.active_node ? 'active' : 'neutral');
      const dotHtml = data.active_node ? '<span class="live-dot"></span>' : '<span class="live-dot live-dot-off"></span>';
      activeBadge.innerHTML = `${dotHtml}${data.active_node || 'nenhum ativo'}`;
    }

    const proxyOk = data.proxy.ok;
    const web01Ok = data.web_frontends[0].ok;
    const web02Ok = data.web_frontends[1].ok;
    const dbOk = data.database.ok;

    setNodeOk('nodeProxy', proxyOk);
    setText('proxyMessage', shortMsg(`${data.proxy.message}${data.proxy.latency_ms ? ` • ${data.proxy.latency_ms}ms` : ''}`));

    const web01 = data.web_frontends[0];
    const web02 = data.web_frontends[1];
    setNodeOk('nodeWeb01', web01Ok);
    setNodeOk('nodeWeb02', web02Ok);
    setText('web01Message', shortMsg(`${web01.message}${web01.latency_ms ? ` • ${web01.latency_ms}ms` : ''}`));
    setText('web02Message', shortMsg(`${web02.message}${web02.latency_ms ? ` • ${web02.latency_ms}ms` : ''}`));

    setNodeOk('nodeDb', dbOk);
    setText('dbMessage', shortMsg(data.database.message || '--'));

    const srv01 = (data.ha.nodes || []).find(n => n.name === 'zbx-node-01') || { status: 'unknown', lastaccess: '--' };
    const srv02 = (data.ha.nodes || []).find(n => n.name === 'zbx-node-02') || { status: 'unknown', lastaccess: '--' };

    const roleOf = s => (s.status === 'active' ? 'active' : s.status === 'standby' ? 'standby' : 'down');
    const srv01Role = roleOf(srv01);
    const srv02Role = roleOf(srv02);
    const srv01Down = srv01Role === 'down';
    const srv02Down = srv02Role === 'down';

    setNodeRole('nodeSrv01', srv01Role);
    setNodeRole('nodeSrv02', srv02Role);
    setRoleFlag('srv01Role', srv01.status);
    setRoleFlag('srv02Role', srv02.status);
    setText('srv01Message', shortMsg(`${(srv01.status || 'sem dados').toUpperCase()} • ${srv01.lastaccess || '--'}`));
    setText('srv02Message', shortMsg(`${(srv02.status || 'sem dados').toUpperCase()} • ${srv02.lastaccess || '--'}`));

    setNodeOk('nodeHost', data.demo_host.ok);
    setText('hostMessage', shortMsg(`${data.demo_host.message}${data.demo_host.age_seconds != null ? ` • ${data.demo_host.age_seconds}s` : ''}`));

    /* ---- links: um segmento só "flui" se origem E destino estiverem OK.
       "idle" é reservado para o caminho srv->host quando o nó está de pé mas em standby. ---- */
    setLinkState('linkProxyWeb01', 'dotProxyWeb01', 'breakProxyWeb01', proxyOk && web01Ok ? 'flow' : 'down');
    setLinkState('linkProxyWeb02', 'dotProxyWeb02', 'breakProxyWeb02', proxyOk && web02Ok ? 'flow' : 'down');
    setLinkState('linkWeb01Db', 'dotWeb01Db', 'breakWeb01Db', web01Ok && dbOk ? 'flow' : 'down');
    setLinkState('linkWeb02Db', 'dotWeb02Db', 'breakWeb02Db', web02Ok && dbOk ? 'flow' : 'down');

    setLinkState('linkDbSrv01', 'dotDbSrv01', 'breakDbSrv01', dbOk && !srv01Down ? 'flow' : 'down');
    setLinkState('linkDbSrv02', 'dotDbSrv02', 'breakDbSrv02', dbOk && !srv02Down ? 'flow' : 'down');

    setLinkState('linkSrv01Host', 'dotSrv01Host', 'breakSrv01Host', srv01Down ? 'down' : (srv01Role === 'active' ? 'flow' : 'idle'));
    setLinkState('linkSrv02Host', 'dotSrv02Host', 'breakSrv02Host', srv02Down ? 'down' : (srv02Role === 'active' ? 'flow' : 'idle'));

    /* ---- alerta de conectividade geral ---- */
    const coreDown = !proxyOk && !web01Ok && !web02Ok;
    if (coreDown || !dbOk) {
      showConnectivityAlert('⚠ Não consegui falar com os outros serviços agora. Confira se todos os containers do lab foram iniciados juntos.');
    } else {
      showConnectivityAlert(null);
    }

    /* ---- failover detection ---- */
    const currentActive = data.active_node;
    if (currentActive && lastKnownActive && currentActive !== lastKnownActive) {
      showFailoverBanner(lastKnownActive, currentActive);
      updateLastEvent(lastKnownActive, currentActive);
    }
    if (currentActive) lastKnownActive = currentActive;

    renderFallback(data, srv01, srv02);
  } catch (err) {
    console.error(err);
    setText('updatedAt', 'falha ao atualizar');
  }
}

window.addEventListener('resize', scaleCanvas);
scaleCanvas();
refresh();
setInterval(refresh, 5000);
