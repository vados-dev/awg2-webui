# AWG 2.0 Web UI — Handoff (сессия 7, 2026-06-05)

## Статус: Backend v8 готов ✅ | Frontend PENDING ⏳ | CHR: v7 running

---

## Что сделано в этой сессии

### 1. Патч `<c>` тега в amneziawg-go
- `patches/obf_counter.go` — `counterObf` (atomic.Uint32, 4 байта LE)
- `patches/obf_counter_test.go` — 6 unit-тестов (8/8 на ARM)
- `Dockerfile` Stage 1: awk-патч + `go test TestCounterObf` перед сборкой
- `<c>` скрыт в UI (`display:none`) — клиенты AWG не поддерживают
- `cps_generator.py` — `<c>` удалён из генераторов с TODO-комментарием

### 2. tini + supervisord fix
- `ENTRYPOINT ["/sbin/tini", "--", "/app/scripts/start.sh"]`
- `nginx-log-clean` → supervisord `[program]` вместо `& bg`
- "reaped unknown pid" исчез

### 3. Новые backend функции (app.py) — НЕ В UI ЕЩЁ

**Хелперы** (добавлены после `_fmt_handshake`):

| Функция | Что делает |
|---------|-----------|
| `_awg_uptime()` | uptime amneziawg-go через /proc/stat |
| `_awg_version()` | `amneziawg-go --version` |
| `_system_resources()` | /proc/loadavg + /proc/meminfo |
| `_fmt_uptime(secs)` | "1d 2h 3m" |
| `_update_traffic(rx,tx,peers)` | Rolling 24h (global + per-peer) |
| `_traffic_24h()` | Дельта за 24ч |
| `_get_geo(ip)` | ip-api.com, TTL 1ч, emoji флаг |
| `_ping_peer(ip)` | ping -c1 -W1, возвращает ms |
| `_detect_cps_profile(i1)` | QUIC/TLS/DTLS/SIP/Noise_IK по hex |
| `_check_alerts(...)` | AWG down + peer no handshake >2h |

**Новые поля в `/api/server/status`:**
```
uptime_secs, uptime_str, version
load_avg, mem_total/used/pct, mem_used_str, mem_total_str
rx_24h, tx_24h
conf_params: {H1-H4, S1-S4, Jc, Jmin, Jmax, I1, I2}
cps_profile: "QUIC Initial" / "TLS 1.3" / etc.
alerts: [{level, msg}, ...]
```

**Новые endpoints:**

| Method | Path | Описание |
|--------|------|---------|
| GET | `/api/peers/<key>/traffic` | История трафика 24ч для Chart.js |
| GET | `/api/peers/<key>/geo` | {country, cc, flag, ip} |
| GET | `/api/peers/<key>/ping` | {latency_ms, ip} |
| POST | `/api/server/regen_cps` | Пересоздать I1-I5 без смены ключей |

---

## ❌ СЛЕДУЮЩИЙ ШАГ — Frontend (templates/index.html)

### 1. Новые карточки в Server Status (данные уже в API)

```html
<!-- добавить в .stat-cards-row рядом с TOTAL RX/TX -->
<div class="stat-card">
  <div class="stat-label">UPTIME</div>
  <div class="stat-value" id="s-uptime">—</div>
</div>
<div class="stat-card">
  <div class="stat-label">VERSION</div>
  <div class="stat-value small" id="s-version">—</div>
</div>
<div class="stat-card">
  <div class="stat-label">LOAD AVG</div>
  <div class="stat-value" id="s-load">—</div>
</div>
<div class="stat-card">
  <div class="stat-label">RAM</div>
  <div class="stat-value" id="s-ram">—</div>
  <div class="progress-bar"><div id="s-ram-bar" style="width:0%"></div></div>
</div>
<div class="stat-card">
  <div class="stat-label">RX 24H</div>
  <div class="stat-value green" id="s-rx24">—</div>
</div>
<div class="stat-card">
  <div class="stat-label">TX 24H</div>
  <div class="stat-value orange" id="s-tx24">—</div>
</div>
```

JS в `updateStatus(data)`:
```js
document.getElementById('s-uptime').textContent = data.uptime_str || '—';
document.getElementById('s-version').textContent = data.version || '—';
document.getElementById('s-load').textContent = (data.load_avg||0).toFixed(2);
document.getElementById('s-ram').textContent =
  `${data.mem_used_str} / ${data.mem_total_str} (${data.mem_pct}%)`;
document.getElementById('s-ram-bar').style.width = (data.mem_pct||0) + '%';
document.getElementById('s-rx24').textContent = data.rx_24h || '0 B';
document.getElementById('s-tx24').textContent = data.tx_24h || '0 B';
```

### 2. CPS Info + Regenerate CPS кнопка

```html
<div class="cps-info-bar">
  <span>Profile: <strong id="s-cps-profile">—</strong></span>
  <span>H1: <code id="s-h1">—</code></span>
  <span>Jc: <code id="s-jc">—</code></span>
  <span>Jmin/Jmax: <code id="s-jmin">—</code>/<code id="s-jmax">—</code></span>
  <button id="btn-regen-cps" onclick="regenCps()">↻ Regenerate CPS</button>
</div>
```

JS:
```js
// в updateStatus(data):
const p = data.conf_params || {};
document.getElementById('s-cps-profile').textContent = data.cps_profile || '—';
document.getElementById('s-h1').textContent = p.H1 || '—';
document.getElementById('s-jc').textContent = p.Jc || '—';
document.getElementById('s-jmin').textContent = p.Jmin || '—';
document.getElementById('s-jmax').textContent = p.Jmax || '—';

async function regenCps() {
  const btn = document.getElementById('btn-regen-cps');
  btn.disabled = true; btn.textContent = '...';
  const r = await fetch('/api/server/regen_cps', {method:'POST', headers:authHeaders()});
  const d = await r.json();
  btn.disabled = false; btn.textContent = '↻ Regenerate CPS';
  document.getElementById('s-cps-profile').textContent = d.cps_profile;
  showToast('CPS regenerated: ' + d.cps_profile);
}
```

### 3. Alerts блок (вверху дашборда, под Server Status)

```html
<div id="alerts-container" class="alerts-block"></div>
```

CSS:
```css
.alert-error { background: rgba(239,68,68,0.15); border-left: 3px solid #ef4444; }
.alert-warn  { background: rgba(245,158,11,0.15); border-left: 3px solid #f59e0b; }
```

JS в `updateStatus(data)`:
```js
document.getElementById('alerts-container').innerHTML =
  (data.alerts||[]).map(a =>
    `<div class="alert alert-${a.level}">⚠ ${a.msg}</div>`
  ).join('');
```

### 4. Флаг + пинг в строке пира

В функции рендера пира — после имени:
```html
<span class="peer-flag" id="flag-PUBKEY"></span>
<span class="peer-latency" id="ping-PUBKEY">—</span>
```

JS (lazy load при рендере):
```js
async function loadPeerExtras(key) {
  const [geo, ping] = await Promise.all([
    fetch(`/api/peers/${key}/geo`, {headers:authHeaders()}).then(r=>r.json()),
    fetch(`/api/peers/${key}/ping`, {headers:authHeaders()}).then(r=>r.json()),
  ]);
  const flagEl = document.getElementById(`flag-${key.replace(/[+/=]/g,'_')}`);
  const pingEl = document.getElementById(`ping-${key.replace(/[+/=]/g,'_')}`);
  if (flagEl) flagEl.textContent = geo.flag || '';
  if (pingEl) pingEl.textContent = ping.latency >= 0
    ? ping.latency.toFixed(1) + ' ms' : '✗';
}
```

### 5. График трафика пира (Chart.js modal)

Chart.js уже подключен. Добавить:
```js
async function showPeerChart(key) {
  const r = await fetch(`/api/peers/${key}/traffic`, {headers:authHeaders()});
  const raw = await r.json();
  if (!raw.length) { showToast('No traffic data yet'); return; }

  const labels = raw.map(p => new Date(p.ts*1000).toLocaleTimeString());
  const rx = raw.map(p => p.rx / 1024);
  const tx = raw.map(p => p.tx / 1024);

  // Показать в modal с canvas #trafficChart
  openModal('traffic-modal');
  new Chart(document.getElementById('trafficChart'), {
    type: 'line',
    data: {
      labels,
      datasets: [
        {label: 'RX KiB', data: rx, borderColor: '#4ade80'},
        {label: 'TX KiB', data: tx, borderColor: '#f59e0b'},
      ]
    },
    options: { responsive: true, animation: false }
  });
}
```

---

## CHR состояние

- SSH: `194.116.172.251:2222`, claude / P@shamar12
- Контейнер **v7** (index 0): root-dir `disk1/docker/awg2-webui7`, **running** ✅
- Конфиг: 3 пира (iphone, disabled, Mac) восстановлен
- Web UI: https://194.116.172.251:9080 (admin / AmneziaTest2026)
- **v8 на CHR НЕ задеплоен** — деплоить после frontend

**Деплой v8 на CHR:**
```bash
docker build --no-cache --platform linux/amd64 -t awg2-webui-v8:amd64 .
docker save awg2-webui-v8:amd64 -o ~/Desktop/awg2-webui-chr-v8.tar
scp -P 2222 ~/Desktop/awg2-webui-chr-v8.tar claude@194.116.172.251:disk1/awg2-webui-chr-v8.tar
# SSH → /container/stop 0 → /container/remove 0
# → /container/add file=disk1/awg2-webui-chr-v8.tar interface=veth-awgui
#   envlist=awgui-env root-dir=disk1/docker/awg2-webui8 mounts="" logging=yes
#   start-on-boot=yes comment="AWG 2.0 Web UI v8"
# → ждём импорт → /container/start [find comment~"v8"]
# → копируем конфиг: sftp awg0.conf → /disk1/docker/awg2-webui8/etc/amnezia/amneziawg/
```

---

## Файловая структура

```
awg2-webui/
├── app.py                  ✅ backend v8 (все новые хелперы + endpoints)
├── cps_generator.py        ✅ <c> убран, закомментирован
├── templates/index.html    ⏳ UI (нужен frontend)
├── start.sh                ✅ tini, без bg subshell
├── config/supervisord.conf ✅ nginx-log-clean как program
├── Dockerfile              ✅ tini + <c> патч
├── patches/obf_counter.go  ✅ <c> реализация
├── patches/obf_counter_test.go ✅ тесты
├── backup/awg0.conf.bak    ✅ 3 пира
└── test-c-tag.sh           ✅ 8 тестов
```
