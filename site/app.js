(() => {
  const cfg = window.WINUTIL_CONFIG;
  const state = {
    token: sessionStorage.getItem('winutil.agentToken') || '',
    connected: false,
    tweaks: [],
    category: 'Dashboard',
    profile: 'safe',
    scan: {},
    selected: new Set(),
    jobTimer: null,
    demo: false
  };

  const $ = id => document.getElementById(id);
  const api = path => `${cfg.agentUrl}${path}`;

  const navItems = [
    ['Dashboard', 'System overview'],
    ['Privacy', 'Privacy controls'],
    ['Performance', 'Performance & power'],
    ['Cleanup', 'Storage cleanup'],
    ['Debloat', 'Optional apps'],
    ['Network', 'Network repair'],
    ['Services', 'Windows services'],
    ['Maintenance', 'Repair tools'],
    ['Security', 'Security status'],
    ['Restore', 'Transactions & rollback']
  ];

  function log(message) {
    const line = `[${new Date().toLocaleTimeString()}] ${message}`;
    const box = $('logBox');
    box.textContent = `${line}\n${box.textContent}`.slice(0, 12000);
  }

  function setConnection(connected, text = null) {
    state.connected = connected;
    const el = $('connectionState');
    el.className = `connection ${connected ? 'connected' : 'disconnected'}`;
    el.textContent = connected ? `● ${text || 'Connected'}` : `● ${text || 'Offline'}`;
  }

  async function request(path, options = {}, auth = true) {
    const headers = new Headers(options.headers || {});
    headers.set('Accept', 'application/json');
    if (options.body) headers.set('Content-Type', 'application/json');
    if (auth && state.token) headers.set('X-WinUtil-Token', state.token);    const res = await fetch(api(path), { ...options, headers });
    if (!res.ok) {
      let message = `${res.status} ${res.statusText}`;
      try { const data = await res.json(); message = data.error || data.message || message; } catch {}
      throw new Error(message);
    }
    return res.json();
  }

  async function connect() {
    try {
      const health = await request('/api/v1/health', {}, false);
      if (!state.token) {
        $('connectDialog').showModal();
        return false;
      }
      await request('/api/v1/status');
      state.demo = false;
      setConnection(true, `Agent ${health.version}`);
      log(`Agent connected: ${health.version}`);
      await loadTweaks();
      await renderDashboard();
      return true;
    } catch (e) {
      state.demo = true;
      setConnection(false, 'Demo mode');
      try { state.tweaks = await fetch('demo-tweaks.json').then(r => r.json()); } catch {}
      renderNav();
      renderTweaks();
      await renderDashboard();
      log('Agent unavailable; static demo mode enabled.');
      return false;
    }
  }

  async function loadTweaks() {
    state.tweaks = await request('/api/v1/tweaks');
    renderNav();
    renderTweaks();
  }

  function renderNav() {
    $('nav').innerHTML = navItems.map(([name, sub]) => `<button class="${state.category === name ? 'active' : ''}" data-cat="${name}"><span>${name}</span></button>`).join('');
    $('nav').querySelectorAll('button').forEach(btn => btn.addEventListener('click', () => selectCategory(btn.dataset.cat)));
  }

  function selectCategory(category) {
    state.category = category;
    $('pageTitle').textContent = category;
    $('dashboard').classList.toggle('active', category === 'Dashboard');
    $('tweaksPage').classList.toggle('active', category !== 'Dashboard');
    renderNav();
    if (category === 'Dashboard') renderDashboard(); else if (category === 'Restore') renderRestore(); else renderTweaks();
  }

  function categoryTweaks() {
    return state.tweaks.filter(t => t.category.toLowerCase() === state.category.toLowerCase());
  }

  function renderTweaks() {
    if (state.category === 'Dashboard') return;
    const items = categoryTweaks();
    $('tweaksPage').innerHTML = `
      <div class="panel">
        <div class="tweak-toolbar">
          <input id="tweakSearch" class="text-input search" placeholder="Tweak ara..." autocomplete="off">
          <button id="selectAll" class="btn secondary">Select visible</button>
          <button id="clearAll" class="btn secondary">Clear</button>
        </div>
        <div id="tweakGrid" class="tweak-grid"></div>
      </div>`;
    const search = $('tweakSearch');
    const draw = () => {
      const q = search.value.toLowerCase().trim();
      const filtered = items.filter(t => `${t.name} ${t.description} ${t.tags.join(' ')}`.toLowerCase().includes(q));
      $('tweakGrid').innerHTML = filtered.map(tweakCard).join('');
      $('tweakGrid').querySelectorAll('input[type=checkbox]').forEach(cb => cb.addEventListener('change', e => {
        const id = e.target.dataset.id;
        if (e.target.checked) state.selected.add(id); else state.selected.delete(id);
      }));
    };
    search.addEventListener('input', draw);
    $('selectAll').addEventListener('click', () => { items.filter(t => t.name.toLowerCase().includes(search.value.toLowerCase())).forEach(t => state.selected.add(t.id)); draw(); });
    $('clearAll').addEventListener('click', () => { items.forEach(t => state.selected.delete(t.id)); draw(); });
    draw();
  }

  function tweakCard(t) {
    const risk = (t.risk || 'Low').toLowerCase();
    const scan = state.scan[t.id];
    const checked = state.selected.has(t.id) ? 'checked' : '';
    const status = scan ? `<div class="status-line">Status: <strong>${escapeHtml(scan.status || 'Unknown')}</strong>${scan.message ? ` — ${escapeHtml(scan.message)}` : ''}</div>` : `<div class="status-line">Not scanned</div>`;
    return `<article class="tweak-card">
      <div class="tweak-head"><input class="tweak-checkbox" type="checkbox" data-id="${t.id}" ${checked}><div><div class="tweak-name">${escapeHtml(t.name)}</div><div class="tweak-desc">${escapeHtml(t.description)}</div></div></div>
      <div class="badges"><span class="badge ${risk}">${escapeHtml(t.risk)}</span><span class="badge">${escapeHtml(t.scope)}</span>${t.reversible ? '<span class="badge">Reversible</span>' : '<span class="badge">No auto-rollback</span>'}</div>
      ${status}
    </article>`;
  }


  async function renderRestore() {
    try {
      const transactions = await request('/api/v1/transactions');
      const rows = transactions.map(tx => `
        <div class="tweak-card">
          <div class="tweak-name">${escapeHtml(tx.transactionId)}</div>
          <div class="tweak-desc">${escapeHtml(tx.status)} · ${escapeHtml(tx.createdUtc)}</div>
          <div class="badges"><span class="badge">${tx.reversible ? 'Reversible' : 'Partial / non-reversible'}</span></div>
          ${tx.reversible && tx.status !== 'RolledBack' ? `<button class="btn secondary rollback-btn" data-tx="${escapeHtml(tx.transactionId)}">Rollback reversible changes</button>` : ''}
        </div>`).join('');
      $('tweaksPage').innerHTML = `<div class="panel"><div class="eyebrow">RESTORE CENTER</div><h2>Transaction history</h2><p class="muted">Rollback only restores changes marked reversible by the local engine. Irreversible actions such as Appx removal are not recreated automatically.</p><div class="tweak-grid">${rows || '<div class="muted">No transactions found.</div>'}</div></div>`;
      $('tweaksPage').querySelectorAll('.rollback-btn').forEach(btn => btn.addEventListener('click', async () => {
        const tx = btn.dataset.tx;
        if (!confirm(`Rollback transaction ${tx}?`)) return;
        try {
          const job = await request(`/api/v1/rollback/${tx}`, {method:'POST'});
          log(`Rollback job started: ${job.id}`);
          pollJob(job.id);
        } catch (e) { log(`Rollback failed: ${e.message}`); }
      }));
    } catch (e) {
      $('tweaksPage').innerHTML = `<div class="panel"><h2>Restore Center</h2><p class="muted">${escapeHtml(e.message)}</p></div>`;
    }
  }

  async function scan() {
    if (!state.connected) { await connect(); if (!state.connected) return; }
    const ids = state.tweaks.map(t => t.id);
    const result = await request('/api/v1/scan', { method: 'POST', body: JSON.stringify({ tweakIds: ids }) });
    state.scan = Object.fromEntries((result.data || []).map(x => [x.id, x]));
    log('Full scan completed.');
    renderTweaks();
    renderDashboard();
  }

  async function preview() {
    if (!state.selected.size) { log('Preview: no tweaks selected.'); return; }

    if (state.demo || !state.connected) {
      // Demo mode runs the same policy rules client-side so the plan can be
      // demonstrated without a Windows machine. No state is ever read or written.
      const allowed = { safe: ['Low'], balanced: ['Low', 'Medium'], aggressive: ['Low', 'Medium', 'High'] }[state.profile];
      const chosen = state.tweaks.filter(t => state.selected.has(t.id));
      const blocked = chosen.filter(t => !allowed.includes(t.risk));

      log(`Plan (${state.profile}, demo): ${chosen.length - blocked.length} change(s), ${blocked.length} blocked, ${chosen.some(t => !t.reversible) ? 'contains irreversible steps' : 'fully reversible'}. Demo mode reads nothing and changes nothing.`);
      blocked.forEach(t => log(`  blocked — ${t.id}: risk '${t.risk}' is not permitted by the '${state.profile}' profile.`));
      return;
    }

    // /api/v1/plan is a dry run. Unlike /preview it also returns the tweaks the
    // profile refuses, with the reason, instead of silently dropping them.
    const result = await request('/api/v1/plan', { method: 'POST', body: JSON.stringify({ tweakIds: [...state.selected], profile: state.profile }) });
    const plan = result.data || {};
    const items = plan.items || [];

    items.forEach(x => { state.scan[x.id] = x; });
    state.plan = plan;

    log(`Plan (${plan.profile}): ${plan.actionableCount} change(s), ${plan.blockedCount} blocked, restore point ${plan.requiresRestorePoint ? 'required' : 'not required'}, ${plan.fullyReversible ? 'fully reversible' : 'contains irreversible steps'}. Nothing was changed.`);

    items.filter(x => x.status === 'BlockedByPolicy').forEach(x => log(`  blocked — ${x.id}: ${x.message}`));

    renderTweaks();
  }

  async function applySelected() {
    if (state.demo || !state.connected) { log('Apply disabled in demo/offline mode. Connect the local agent first.'); return; }
    if (!state.selected.size) { log('Apply: no tweaks selected.'); return; }
    if (!state.connected) { await connect(); if (!state.connected) return; }
    const confirmText = `Selected: ${state.selected.size}\nProfile: ${state.profile}\n\nSystem changes will be logged. Continue?`;
    if (!window.confirm(confirmText)) return;
    const result = await request('/api/v1/apply', { method: 'POST', body: JSON.stringify({ tweakIds: [...state.selected], profile: state.profile, allowWithoutRestorePoint: false }) });
    log(`Apply job started: ${result.id}`);
    pollJob(result.id);
  }

  async function pollJob(id) {
    if (state.jobTimer) clearInterval(state.jobTimer);
    state.jobTimer = setInterval(async () => {
      try {
        const job = await request(`/api/v1/jobs/${id}`);
        $('progressBar').style.width = `${job.progress || 0}%`;
        $('progressLabel').textContent = `${job.progress || 0}%`;
        $('stageLabel').textContent = job.stage || job.state;
        if (job.state === 'Completed' || job.state === 'Failed') {
          clearInterval(state.jobTimer);
          state.jobTimer = null;
          log(`Job ${id}: ${job.state} — ${job.message || ''}`);
          await scan();
        }
      } catch (e) {
        clearInterval(state.jobTimer);
        state.jobTimer = null;
        log(`Job polling failed: ${e.message}`);
      }
    }, 900);
  }

  async function renderDashboard() {
    let status = null;
    try { status = await request('/api/v1/status'); } catch {}
    const applied = Object.values(state.scan).filter(x => x.status === 'AlreadyApplied').length;
    const changes = Object.values(state.scan).filter(x => x.status === 'ChangeRequired').length;
    $('dashboard').innerHTML = `
      <div class="hero">
        <div class="panel hero-main">
          <div><div class="eyebrow">WINDOWS 10 / 11</div><h2>Kontrol, bakım ve gizliliği tek bir güvenli çalışma alanında topla.</h2><p class="muted">Statik web arayüzü + yalnızca loopback üzerinde çalışan yerel agent. Demo modunda hiçbir sistem değişikliği yapılmaz.</p></div>
          <div class="health-grid">
            ${healthItem('Machine', status?.machineName || '—')}
            ${healthItem('User', status?.userName || '—')}
            ${healthItem('Architecture', status?.architecture || '—')}
            ${healthItem('Admin', status ? String(status.isAdministrator ? 'YES' : 'NO') : '—')}
          </div>
        </div>
        <div class="panel">
          <div class="eyebrow">TWEAK STATE</div>
          <div class="metric"><div class="metric-number">${changes}</div><div class="metric-label">changes required</div></div>
          <div class="muted">${applied} tweak already matches the target state.</div>
          <div style="margin-top:18px" class="muted">Profile: <strong>${state.profile}</strong></div>
        </div>
      </div>`;
  }

  function healthItem(label, value) { return `<div class="health-item"><span>${label}</span><strong>${escapeHtml(String(value))}</strong></div>`; }
  function escapeHtml(value) { return String(value).replace(/[&<>'"]/g, c => ({ '&':'&amp;','<':'&lt;','>':'&gt;','\'':'&#39;','"':'&quot;' }[c])); }

  $('connectBtn').addEventListener('click', () => $('connectDialog').showModal());
  $('cancelConnect').addEventListener('click', () => $('connectDialog').close());
  $('saveToken').addEventListener('click', async () => {
    state.token = $('tokenInput').value.trim();
    if (!state.token) return;
    sessionStorage.setItem('winutil.agentToken', state.token);
    $('connectDialog').close();
    await connect();
  });
  $('profile').addEventListener('change', e => { state.profile = e.target.value; log(`Profile changed: ${state.profile}`); });
  $('scanBtn').addEventListener('click', () => scan().catch(e => log(`Scan failed: ${e.message}`)));
  $('previewBtn').addEventListener('click', () => preview().catch(e => log(`Preview failed: ${e.message}`)));
  $('applyBtn').addEventListener('click', () => applySelected().catch(e => log(`Apply failed: ${e.message}`)));
  $('clearLog').addEventListener('click', () => $('logBox').textContent = '');

  renderNav();
  selectCategory('Dashboard');
  $('tokenInput').value = state.token;
  connect().catch(() => {});
  log('WinUtil NG static site ready.');
})();
