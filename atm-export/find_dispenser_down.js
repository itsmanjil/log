/*
 * ATM Monitoring: find "Dispenser down" ATMs on ALL pages and tick their checkboxes.
 * It NEVER sends a command: after checking the list, open Group management and choose
 * the command yourself (e.g. "Close and block").
 *
 * How it reads the error details: first from the page itself (tooltip text that is already
 * there but hidden), otherwise by hovering each red error icon the way the mouse does and
 * reading the "Devices errors details for ..." box that appears.
 * It goes through every page (like Export ATMs, also when the page auto-refreshes) reading
 * the DEV (device problem) error icons, then lists every Dispenser-down ATM. The website keeps ticks
 * only on the page on screen, so it ticks only the ones on the page it ends on and lists the
 * others; to tick them all, click DEV (all device problems on one page) first.
 */
(async () => {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const clean = s => (s || '').replace(/\s+/g, ' ').trim();
  const PAGER = '.rich-datascr, .dr-dscr, .ui-paginator, [class*="datascr"], [class*="paginator"]';
  const DOWN_RE = /dispenser\s*down/i;
  const PAGE_TIMEOUT_MS = 20000;

  function findTable() {
    let best = null, bestN = 0;
    for (const t of document.querySelectorAll('table')) {
      const n = [...t.rows].filter(r => r.cells.length >= 6).length;
      if (n > bestN) { best = t; bestN = n; }
    }
    return best;
  }
  const isPager = tr => !!tr.closest('tfoot') || !!tr.querySelector(PAGER);
  const dataRows = t => [...t.rows].filter(tr => !isPager(tr) && !tr.closest('thead') && !tr.querySelector('th') && tr.cells.length >= 6);
  if (!findTable()) { alert('Could not find the ATM table on this page.'); return; }

  // Text already in the cell: hidden tooltip text, title / alt, mouse-over scripts.
  function textInCell(td) {
    const bits = [td.textContent];
    for (const el of [td, ...td.querySelectorAll('*')]) {
      for (const a of ['title', 'alt', 'onmouseover', 'onmouseenter', 'data-tooltip']) {
        const v = el.getAttribute && el.getAttribute(a);
        if (v) bits.push(v);
      }
    }
    return clean(bits.join(' '));
  }

  // Hover an icon and wait for the "... details for <pid>" box.
  async function hoverText(icon, pid) {
    const fire = type => icon.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, view: window }));
    ['mouseover', 'mouseenter', 'mousemove'].forEach(fire);
    let found = '';
    for (let i = 0; i < 25 && !found; i++) {
      await sleep(150);
      for (const el of document.querySelectorAll('div, span, table, td')) {
        const t = el.textContent || '';
        if (pid && t.includes(pid) && /details/i.test(t) && t.length < 600 && el.children.length < 40) {
          found = clean(t);
          break;
        }
      }
    }
    ['mouseout', 'mouseleave'].forEach(fire);
    await sleep(100);
    return found;
  }

  const isErrorIcon = img => !/square|cassette|info/i.test(img.getAttribute('src') || '');
  // DEV column from the header; headings are compared on letters only ("DEV ⇕" = DEV)
  const letters = s => clean(s).toUpperCase().replace(/[^A-Z]/g, '');
  function errorColumns(table) {
    let cols = [];
    for (const tr of [...table.rows].filter(r => !isPager(r) && (r.closest('thead') || r.querySelector('th')))) {
      const idx = [...tr.cells].map((c, i) => letters(c.innerText) === 'DEV' ? i : -1).filter(i => i >= 0);
      if (idx.length && [...tr.cells].some(c => letters(c.innerText) === 'NAME')) cols = idx;
    }
    return cols;
  }

  const found = new Map();   // tid -> { name, page, ticked }
  const unread = new Map();  // tid -> name
  const checkedTids = new Set();

  async function scanPage(pageNo) {
    const table = findTable();
    const errCols = errorColumns(table);
    for (const tr of dataRows(table)) {
      const cells = [...tr.cells];
      const tidCell = cells.find(td => /^PRV\d+/i.test(clean(td.innerText)));
      if (!tidCell) continue;
      const tid = clean(tidCell.innerText);
      const pid = (tid.match(/\((\d+)\)/) || [])[1] || '';
      const name = clean((cells[cells.indexOf(tidCell) - 1] || {}).innerText);
      const t0 = cells.indexOf(tidCell);
      // DEV only: the header column (else the cell right after REMOTE ADDRESS)
      const cand = new Set(errCols.length ? errCols : [t0 + 2]);
      const iconCells = [...cand].map(i => cells[i])
        .filter(td => td && [...td.querySelectorAll('img')].some(isErrorIcon));
      if (!iconCells.length) { checkedTids.add(tid); continue; }
      let text = iconCells.map(textInCell).join(' | ');
      if (!DOWN_RE.test(text)) {
        for (const td of iconCells) {
          if (!tr.isConnected) break;
          const t = await hoverText([...td.querySelectorAll('img')].find(isErrorIcon), pid);
          if (t) text += ' | ' + t;
        }
      }
      // the page auto-refreshed while hovering: this page has to be checked again
      if (!tr.isConnected && !/details|dispenser/i.test(text)) return false;
      checkedTids.add(tid);
      if (!/details|dispenser|error|reader|printer|down/i.test(text)) { unread.set(tid, name); continue; }
      unread.delete(tid);
      // nothing is ticked while scanning: the website forgets ticks when the page changes
      if (DOWN_RE.test(text)) found.set(tid, { name, page: pageNo });
    }
    return true;
  }

  // ---------- page bar (same approach as Export ATMs) ----------
  const pagerScopes = () => {
    const p = document.querySelectorAll(PAGER + ', [id*="scroller" i], [id*="pager" i]');
    return p.length ? [...p] : [document.body];
  };
  function activePage() {
    for (const scope of pagerScopes()) {
      const el = [...scope.querySelectorAll('td, a, span, li')].find(e =>
        /(^|[-_ ])(act|active|current|selected)\b/.test((e.className || '').toString().toLowerCase()) && /^\d+$/.test(clean(e.innerText)));
      if (el) return +clean(el.innerText);
    }
    return 0;
  }
  const visited = new Set();
  let lastTried = false;
  function nextControl() {
    for (const scope of pagerScopes()) {
      const els = [...scope.querySelectorAll('td, a, span, button, li')];
      const nums = els.filter(e => e.children.length === 0 && /^\d+$/.test(clean(e.innerText)))
        .map(e => ({ el: e, page: +clean(e.innerText) })).sort((a, b) => a.page - b.page);
      const unreadPage = nums.find(n => !visited.has(n.page));
      if (unreadPage) return unreadPage;
      if (!lastTried) {
        const last = els.find(e => e.children.length === 0 && ['last', '»»', '>>|'].includes(clean(e.innerText).toLowerCase()));
        if (last) { lastTried = true; return { el: last, page: 0 }; }
      }
    }
    for (const scope of pagerScopes()) {
      const next = [...scope.querySelectorAll('td, a, span, button, li')].find(e => {
        const t = clean(e.innerText).toLowerCase(), cls = (e.className || '').toString().toLowerCase();
        return !/dis|inact-btn|ui-state-disabled/.test(cls) && (['›', '>', 'next'].includes(t) || (e.getAttribute('onclick') || '').includes("'next'"));
      });
      if (next) return { el: next, page: 0 };
    }
    return null;
  }
  const signature = () => {
    const t = findTable();
    const r = t ? dataRows(t) : [];
    return r.length ? clean(r[0].innerText) + '#' + clean(r[r.length - 1].innerText) + '#' + r.length : '';
  };
  async function waitForChange(old) {
    const start = Date.now();
    while (Date.now() - start < PAGE_TIMEOUT_MS) {
      await sleep(300);
      const s = signature();
      if (s && s !== old) { await sleep(400); return true; }
    }
    return false;
  }
  const filtered = () => {
    const t = findTable();
    const m = clean(t ? [...t.rows].filter(r => r.closest('thead') || r.querySelector('th')).map(r => r.innerText).join(' ') : '')
      .match(/FILTERED\s+(\d+)/i);
    return m ? +m[1] : 0;
  };

  // ---------- go through every page ----------
  const expected = filtered();
  let page = activePage() || 1;
  visited.add(page);
  if (!(await scanPage(page))) visited.delete(page);
  for (let step = 0, idle = 0; step < 200 && !(expected && checkedTids.size >= expected); step++) {
    if (idle >= 25) break;
    const next = nextControl();
    if (!next) break;
    const before = signature();
    next.el.click();
    if (!(await waitForChange(before))) break;
    page = activePage() || next.page;
    if (page) visited.add(page);
    lastTried = false;
    const n = checkedTids.size;
    if (!(await scanPage(page)) && page) visited.delete(page);
    idle = checkedTids.size > n ? 0 : idle + 1;
  }

  // ---------- tick the ones on the page now on screen ----------
  // (ticks are kept only on the page you are on, so only these can be selected together)
  await sleep(500);
  const tickedNow = [], elsewhere = [];
  const tickRows = () => {
    const t = findTable();
    const map = new Map();
    for (const tr of (t ? dataRows(t) : [])) {
      const tidCell = [...tr.cells].find(td => /^PRV\d+/i.test(clean(td.innerText)));
      if (tidCell) map.set(clean(tidCell.innerText), tr);
    }
    return map;
  };
  let onScreen = tickRows();
  for (const [tid] of found) {
    const tr = onScreen.get(tid);
    const box = tr && tr.cells[1] && tr.cells[1].querySelector('input[type=checkbox]');
    if (box) {
      if (!box.checked) box.click();
      tr.style.outline = '3px solid #ff9800';
    }
  }
  await sleep(1500);  // make sure the ticks stayed (no refresh / re-draw in between)
  onScreen = tickRows();
  for (const [tid, v] of found) {
    const tr = onScreen.get(tid);
    const box = tr && tr.cells[1] && tr.cells[1].querySelector('input[type=checkbox]');
    if (box && box.checked) tickedNow.push(`${tid}  ${v.name}`); else elsewhere.push(`${tid}  ${v.name}  (page ${v.page})`);
  }

  // ---------- report ----------
  let msg = found.size
    ? `"Dispenser down" on ${found.size} ATM(s).\n\n` +
      (tickedNow.length ? `TICKED on the page now on screen (${tickedNow.length}):\n${tickedNow.join('\n')}\n\n` : '') +
      (elsewhere.length ? `NOT ticked - on other pages (${elsewhere.length}):\n${elsewhere.join('\n')}\n\n` +
        'The website keeps ticks only on the page you are on. To select them all at once: click DEV to show ' +
        'all device problems on one page (or filter Problems > Dispenser), then click this bookmark again.\n\n' : '') +
      'Nothing was sent. Check the ticks, then use Group management and choose the command yourself.'
    : 'No ATM shows "Dispenser down".';
  msg += `\n\nChecked ${checkedTids.size}${expected ? ' of ' + expected : ''} ATMs on ${visited.size} page(s).`;
  if (expected && checkedTids.size < expected) msg += ' Not all ATMs could be checked - run it again.';
  if (unread.size) {
    msg += `\n\nCould not read the error details of ${unread.size} ATM(s) with a red icon:\n` +
      [...unread].slice(0, 10).map(([t, n]) => `${t} ${n}`).join('\n') +
      '\nHover one of them and send a photo so this can be fixed.';
  }
  alert(msg);
})();
