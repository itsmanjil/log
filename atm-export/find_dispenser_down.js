/*
 * ATM Monitoring: find "Dispenser down" ATMs on the page on screen and tick their checkboxes.
 * It NEVER sends a command: after checking the list, open Group management and choose
 * the command yourself (e.g. "Open" or "Close and block").
 *
 * It first clicks the DEV (device problem) column heading so all device problems come to the
 * top / on one page (twice if the first click puts them at the bottom), then checks only that
 * page and only the DEV column.
 * The error details come from the page itself (tooltip text already there but hidden), or
 * from hovering each red DEV icon the way the mouse does and reading the
 * "Devices errors details for ..." box.
 * Each tick is sent to the website, so boxes are ticked one at a time: click, wait until the
 * website has recorded it, check it is still ticked, try again if not.
 */
(async () => {
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const clean = s => (s || '').replace(/\s+/g, ' ').trim();
  const PAGER = '.rich-datascr, .dr-dscr, .ui-paginator, [class*="datascr"], [class*="paginator"]';
  const DOWN_RE = /dispenser\s*down/i;
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

  const found = new Map();   // tid -> name
  const unread = new Map();  // tid -> name
  let checked = 0;

  // Read the page; returns false if it auto-refreshed while hovering (then it is read again).
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

  // Tick one ATM like a person would: one click, wait until the website has recorded it
  // (it may redraw the table), check it is still ticked, try again if not.
  async function tick(tid) {
    for (let attempt = 0; attempt < 3; attempt++) {
      const box = boxOf(rowOf(tid));
      if (!box) return false;
      if (!box.checked) {
        box.click();
        await sleep(TICK_WAIT_MS);
      }
      const after = boxOf(rowOf(tid));
      if (after && after.checked) {
        rowOf(tid).style.outline = '3px solid #ff9800';
        return true;
      }
    }
    return false;
  }

  // ---------- click DEV first: all device problems come to the top / on one page ----------
  const signature = () => {
    const t = findTable();
    const r = t ? dataRows(t) : [];
    return r.length ? tidOf(r[0]) + '#' + tidOf(r[r.length - 1]) + '#' + r.length : '';
  };
  async function waitForChange(old) {
    for (const start = Date.now(); Date.now() - start < 20000;) {
      await sleep(300);
      const s = signature();
      if (s && s !== old) { await sleep(600); return true; }
    }
    return false;
  }
  function devHeader() {
    const t = findTable();
    for (const tr of [...t.rows].filter(r => !isPager(r) && (r.closest('thead') || r.querySelector('th')))) {
      if (![...tr.cells].some(c => letters(c.innerText) === 'NAME')) continue;
      const cell = [...tr.cells].find(c => letters(c.innerText) === 'DEV');
      if (cell) return cell.querySelector('a, span[onclick], div[onclick], img[onclick]') || cell;
    }
    return null;
  }
  const devRowsOnTop = () => {   // are the first rows the ones with a red DEV icon?
    const t = findTable();
    const cols = devColumns(t);
    const top = dataRows(t).slice(0, 3);
    return top.length > 0 && top.every(tr => {
      const cells = [...tr.cells];
      const t0 = cells.findIndex(td => /^PRV\d+/i.test(clean(td.innerText)));
      const td = cells[(cols.length ? cols[0] : t0 + 2)];
      return td && [...td.querySelectorAll('img')].some(isErrorIcon);
    });
  };
  let devClicks = 0;
  for (let i = 0; i < 2 && !devRowsOnTop(); i++) {
    const h = devHeader();
    if (!h) break;
    const before = signature();
    h.click();
    devClicks++;
    await waitForChange(before);
  }

  // ---------- read the page on screen (again if an auto-refresh interrupts) ----------
  let complete = false;
  for (let attempt = 0; attempt < 3 && !complete; attempt++) {
    if (attempt) await sleep(1500);
    complete = await scanPage();
  }

  // ---------- tick them, one at a time ----------
  const ticked = [], notTicked = [];
  for (const [tid, name] of found) ((await tick(tid)) ? ticked : notTicked).push(`${tid}  ${name}`);
  await sleep(800);
  // final check: still ticked after everything settled?
  for (let i = ticked.length - 1; i >= 0; i--) {
    const tid = ticked[i].split('  ')[0];
    const box = boxOf(rowOf(tid));
    if (!box || !box.checked) notTicked.push(ticked.splice(i, 1)[0]);
  }

  // ---------- report ----------
  let msg = found.size
    ? `"Dispenser down" on ${found.size} ATM(s).\n\n` +
      (ticked.length ? `TICKED (${ticked.length}):\n${ticked.join('\n')}\n\n` : '') +
      (notTicked.length ? `Could NOT tick (${notTicked.length}) - tick these yourself or click the bookmark again:\n` +
        `${notTicked.join('\n')}\n\n` : '') +
      'Nothing was sent. Open Group management: it should list the ticked ATMs. Check them, then choose the command yourself.'
    : 'No ATM on this page shows "Dispenser down" in the DEV column.';
  msg += `\n\nChecked ${checked} ATMs on this page` +
    (devClicks ? ` (after clicking DEV ${devClicks}x so device problems come first).` : ' (device problems were already first).');
  if (!devRowsOnTop()) msg += '\nNote: the device problems did not come to the top - click DEV yourself and run it again.';
  if (!complete) msg += '\nThe page kept refreshing while checking - click the bookmark again.';
  if (unread.size) {
    msg += `\n\nCould not read the error details of ${unread.size} ATM(s) with a red DEV icon:\n` +
      [...unread].slice(0, 10).map(([t, n]) => `${t} ${n}`).join('\n') +
      '\nHover one of them and send a photo so this can be fixed.';
  }
  alert(msg);
})();
