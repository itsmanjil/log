/*
 * ATM Monitoring: find "Dispenser down" ATMs on ALL pages and tick their checkboxes.
 * It NEVER sends a command: after checking the list, open Group management and choose
 * the command yourself (e.g. "Open" or "Close and block").
 *
 * Only the DEV (device problem) column is read. The error details come from the page itself
 * (tooltip text that is already there but hidden), otherwise from hovering each red DEV icon
 * the way the mouse does and reading the "Devices errors details for ..." box.
 * The website keeps ticks across pages, but each tick is sent to the website: the script ticks
 * one box at a time, waits until it has stuck, and only then moves on / changes page.
 */
(async () => {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const clean = s => (s || '').replace(/\s+/g, ' ').trim();
  const PAGER = '.rich-datascr, .dr-dscr, .ui-paginator, [class*="datascr"], [class*="paginator"]';
  const DOWN_RE = /dispenser\s*down/i;
  const PAGE_TIMEOUT_MS = 20000;
  const TICK_WAIT_MS = 1200;  // time the website gets to record one tick

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
  const tidOf = tr => {
    const c = [...tr.cells].find(td => /^PRV\d+/i.test(clean(td.innerText)));
    return c ? clean(c.innerText) : '';
  };
  const rowOf = tid => { const t = findTable(); return t ? dataRows(t).find(tr => tidOf(tr) === tid) : null; };
  const boxOf = tr => tr && tr.cells[1] ? tr.cells[1].querySelector('input[type=checkbox]') : null;

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
  function devColumns(table) {
    let cols = [];
    for (const tr of [...table.rows].filter(r => !isPager(r) && (r.closest('thead') || r.querySelector('th')))) {
      const idx = [...tr.cells].map((c, i) => letters(c.innerText) === 'DEV' ? i : -1).filter(i => i >= 0);
      if (idx.length && [...tr.cells].some(c => letters(c.innerText) === 'NAME')) cols = idx;
    }
    return cols;
  }

  // Tick one ATM like a person would: one click, then wait until the website has recorded it
  // (it may redraw the row), check it is still ticked, try again if not.
  async function tick(tid) {
    for (let attempt = 0; attempt < 3; attempt++) {
      const box = boxOf(rowOf(tid));
      if (!box) return false;
      if (box.checked) {
        await sleep(attempt ? 0 : 200);
        if (boxOf(rowOf(tid)) && boxOf(rowOf(tid)).checked) return true;
        continue;
      }
      box.click();
      await sleep(TICK_WAIT_MS);
      const after = boxOf(rowOf(tid));
      if (after && after.checked) {
        rowOf(tid).style.outline = '3px solid #ff9800';
        return true;
      }
    }
    return false;
  }

  const found = new Map();   // tid -> { name, page, ticked }
  const unread = new Map();  // tid -> name
  const checkedTids = new Set();

  // Read one page; returns false if the page auto-refreshed while hovering (check it again).
  async function scanPage(pageNo) {
    const table = findTable();
    const cols = devColumns(table);
    const downHere = [];
    for (const tr of dataRows(table)) {
      const cells = [...tr.cells];
      const tidCell = cells.find(td => /^PRV\d+/i.test(clean(td.innerText)));
      if (!tidCell) continue;
      const tid = clean(tidCell.innerText);
      const pid = (tid.match(/\((\d+)\)/) || [])[1] || '';
      const t0 = cells.indexOf(tidCell);
      const name = clean((cells[t0 - 1] || {}).innerText);
      const iconCells = (cols.length ? cols : [t0 + 2]).map(i => cells[i])
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
      if (!tr.isConnected && !/details|dispenser/i.test(text)) return false;
      checkedTids.add(tid);
      if (!/details|dispenser|error|reader|printer|down/i.test(text)) { unread.set(tid, name); continue; }
      unread.delete(tid);
      if (DOWN_RE.test(text)) downHere.push([tid, name]);
    }
    // tick this page's ones before leaving the page
    for (const [tid, name] of downHere) {
      const ok = await tick(tid);
      found.set(tid, { name, page: pageNo, ticked: ok });
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
    return r.length ? tidOf(r[0]) + '#' + tidOf(r[r.length - 1]) + '#' + r.length : '';
  };
  async function waitForChange(old) {
    const start = Date.now();
    while (Date.now() - start < PAGE_TIMEOUT_MS) {
      await sleep(300);
      const s = signature();
      if (s && s !== old) { await sleep(600); return true; }
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
    await sleep(800);  // let the last tick reach the website before changing page
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

  // ---------- report ----------
  const ticked = [...found].filter(([, v]) => v.ticked).map(([tid, v]) => `${tid}  ${v.name}  (page ${v.page})`);
  const failed = [...found].filter(([, v]) => !v.ticked).map(([tid, v]) => `${tid}  ${v.name}  (page ${v.page})`);
  let msg = found.size
    ? `"Dispenser down" on ${found.size} ATM(s).\n\n` +
      (ticked.length ? `TICKED (${ticked.length}):\n${ticked.join('\n')}\n\n` : '') +
      (failed.length ? `Could NOT tick (${failed.length}) - tick these yourself:\n${failed.join('\n')}\n\n` : '') +
      'Nothing was sent. Open Group management: it should list the ticked ATMs. Check them, then choose the command yourself.'
    : 'No ATM shows "Dispenser down" in the DEV column.';
  msg += `\n\nChecked ${checkedTids.size}${expected ? ' of ' + expected : ''} ATMs on ${visited.size} page(s).`;
  if (expected && checkedTids.size < expected) msg += ' Not all ATMs could be checked - run it again.';
  if (unread.size) {
    msg += `\n\nCould not read the error details of ${unread.size} ATM(s) with a red DEV icon:\n` +
      [...unread].slice(0, 10).map(([t, n]) => `${t} ${n}`).join('\n') +
      '\nHover one of them and send a photo so this can be fixed.';
  }
  alert(msg);
})();
