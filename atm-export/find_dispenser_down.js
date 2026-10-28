/*
 * ATM Monitoring: find "Dispenser down" ATMs on ALL pages and tick their checkboxes.
 * It NEVER sends a command: after checking the list, open Group management and choose
 * the command yourself (e.g. "Close and block").
 *
 * How it reads the error details: first from the page itself (tooltip text that is already
 * there but hidden), otherwise by hovering each red error icon the way the mouse does and
 * reading the "Devices errors details for ..." box that appears.
 * It goes through every page (like Export ATMs, also when the page auto-refreshes) and
 * finally lists every Dispenser-down ATM. Whether the ticks on earlier pages are kept after
 * changing page depends on the website - the message says how to check.
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
  function errorColumns(table) {  // DEV / DISP, from the header
    let cols = [];
    for (const tr of [...table.rows].filter(r => !isPager(r) && (r.closest('thead') || r.querySelector('th')))) {
      const idx = [...tr.cells].map((c, i) => /^(DEV|DISP)$/i.test(clean(c.innerText)) ? i : -1).filter(i => i >= 0);
      if (idx.length && [...tr.cells].some(c => /^NAME$/i.test(clean(c.innerText)))) cols = idx;
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
      const iconCells = (errCols.length ? errCols.map(i => cells[i]) : cells.slice(t0 + 2, t0 + 4))
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
      if (DOWN_RE.test(text)) {
        const box = cells[1] && cells[1].querySelector('input[type=checkbox]');
        if (box && !box.checked && box.isConnected) box.click();
        tr.style.outline = '3px solid #ff9800';
        found.set(tid, { name, page: pageNo, ticked: !!box });
      }
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

  // ---------- report ----------
  const list = [...found].map(([tid, v]) => `${tid}  ${v.name}  (page ${v.page})`);
  let msg = list.length
    ? `"Dispenser down" on ${list.length} ATM(s):\n\n${list.join('\n')}\n\n` +
      'Their boxes were ticked page by page (orange border). Nothing was sent.'
    : 'No ATM shows "Dispenser down".';
  msg += `\n\nChecked ${checkedTids.size}${expected ? ' of ' + expected : ''} ATMs on ${visited.size} page(s).`;
  if (expected && checkedTids.size < expected) msg += ' Not all ATMs could be checked - run it again.';
  if (unread.size) {
    msg += `\n\nCould not read the error details of ${unread.size} ATM(s) with a red icon:\n` +
      [...unread].slice(0, 10).map(([t, n]) => `${t} ${n}`).join('\n') +
      '\nHover one of them and send a photo so this can be fixed.';
  }
  if (list.length && visited.size > 1) {
    msg += '\n\nBefore sending a command: go back to an earlier page and check its ticks are still there. ' +
      'If they are gone, the website keeps ticks only on the page you are on - then filter ' +
      'Problems > Dispenser (Search) so they are all on one page and click this bookmark again.';
  }
  alert(msg);
})();
