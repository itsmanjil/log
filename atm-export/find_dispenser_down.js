/*
 * ATM Monitoring: find "Dispenser down" ATMs on the page on screen and tick their checkboxes.
 * It NEVER sends a command: after checking the list, open Group management and choose
 * the command yourself (e.g. "Close and block").
 *
 * Only the page on screen and only the DEV (device problem) column are checked: click DEV on
 * the website first so all device problems are on one page, then click this bookmark.
 * How it reads the error details: first from the page itself (tooltip text that is already
 * there but hidden), otherwise by hovering each red DEV icon the way the mouse does and
 * reading the "Devices errors details for ..." box that appears.
 */
(async () => {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const clean = s => (s || '').replace(/\s+/g, ' ').trim();
  const PAGER = '.rich-datascr, .dr-dscr, .ui-paginator, [class*="datascr"], [class*="paginator"]';
  const DOWN_RE = /dispenser\s*down/i;

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
  function devColumns(table) {
    let cols = [];
    for (const tr of [...table.rows].filter(r => !isPager(r) && (r.closest('thead') || r.querySelector('th')))) {
      const idx = [...tr.cells].map((c, i) => letters(c.innerText) === 'DEV' ? i : -1).filter(i => i >= 0);
      if (idx.length && [...tr.cells].some(c => letters(c.innerText) === 'NAME')) cols = idx;
    }
    return cols;
  }

  const found = new Map();   // tid -> name
  const unread = new Map();  // tid -> name
  let checked = 0;

  // Returns false if the page auto-refreshed while hovering (then it is checked again).
  async function scanPage() {
    found.clear(); unread.clear(); checked = 0;
    const table = findTable();
    const cols = devColumns(table);
    for (const tr of dataRows(table)) {
      const cells = [...tr.cells];
      const tidCell = cells.find(td => /^PRV\d+/i.test(clean(td.innerText)));
      if (!tidCell) continue;
      const tid = clean(tidCell.innerText);
      const pid = (tid.match(/\((\d+)\)/) || [])[1] || '';
      const t0 = cells.indexOf(tidCell);
      const name = clean((cells[t0 - 1] || {}).innerText);
      // DEV only: the header column (else the cell right after REMOTE ADDRESS)
      const iconCells = (cols.length ? cols : [t0 + 2]).map(i => cells[i])
        .filter(td => td && [...td.querySelectorAll('img')].some(isErrorIcon));
      checked++;
      if (!iconCells.length) continue;
      let text = iconCells.map(textInCell).join(' | ');
      if (!DOWN_RE.test(text)) {
        for (const td of iconCells) {
          if (!tr.isConnected) break;
          const t = await hoverText([...td.querySelectorAll('img')].find(isErrorIcon), pid);
          if (t) text += ' | ' + t;
        }
      }
      if (!tr.isConnected && !/details|dispenser/i.test(text)) return false;
      if (!/details|dispenser|error|reader|printer|down/i.test(text)) { unread.set(tid, name); continue; }
      if (DOWN_RE.test(text)) found.set(tid, name);
    }
    return true;
  }

  // ---------- check the page on screen only (again if an auto-refresh interrupts) ----------
  let complete = false;
  for (let attempt = 0; attempt < 3 && !complete; attempt++) {
    if (attempt) await sleep(1500);
    complete = await scanPage();
  }

  // ---------- tick them ----------
  const rowsByTid = () => {
    const t = findTable();
    const map = new Map();
    for (const tr of (t ? dataRows(t) : [])) {
      const tidCell = [...tr.cells].find(td => /^PRV\d+/i.test(clean(td.innerText)));
      if (tidCell) map.set(clean(tidCell.innerText), tr);
    }
    return map;
  };
  let onScreen = rowsByTid();
  for (const [tid] of found) {
    const tr = onScreen.get(tid);
    const box = tr && tr.cells[1] && tr.cells[1].querySelector('input[type=checkbox]');
    if (box) {
      if (!box.checked) box.click();
      tr.style.outline = '3px solid #ff9800';
    }
  }
  await sleep(1500);  // make sure the ticks stayed (no refresh / re-draw in between)
  onScreen = rowsByTid();
  const ticked = [], notTicked = [];
  for (const [tid, name] of found) {
    const tr = onScreen.get(tid);
    const box = tr && tr.cells[1] && tr.cells[1].querySelector('input[type=checkbox]');
    (box && box.checked ? ticked : notTicked).push(`${tid}  ${name}`);
  }

  // ---------- report ----------
  let msg = found.size
    ? `"Dispenser down" on ${found.size} ATM(s).\n\n` +
      (ticked.length ? `TICKED (${ticked.length}):\n${ticked.join('\n')}\n\n` : '') +
      (notTicked.length ? `NOT ticked - the page refreshed meanwhile (${notTicked.length}):\n${notTicked.join('\n')}\n` +
        'Click the bookmark again.\n\n' : '') +
      'Nothing was sent. Check the ticks, then use Group management and choose the command yourself.'
    : 'No ATM on this page shows "Dispenser down" in the DEV column.';
  msg += `\n\nChecked ${checked} ATMs on this page only (click DEV first to have all device problems on one page).`;
  if (!complete) msg += '\nThe page kept refreshing while checking - click the bookmark again.';
  if (unread.size) {
    msg += `\n\nCould not read the error details of ${unread.size} ATM(s) with a red DEV icon:\n` +
      [...unread].slice(0, 10).map(([t, n]) => `${t} ${n}`).join('\n') +
      '\nHover one of them and send a photo so this can be fixed.';
  }
  alert(msg);
})();
