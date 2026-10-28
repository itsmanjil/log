/*
 * ATM Monitoring: find "Dispenser down" ATMs on the current page and tick their checkboxes.
 * It NEVER sends a command: after checking the list, open Group management and choose
 * the command yourself (e.g. "Close and block").
 *
 * How it reads the error details: first from the page itself (tooltip text that is already
 * there but hidden), otherwise by hovering each red error icon the way the mouse does and
 * reading the "Devices errors details for ..." box that appears.
 * Only the page on screen is checked. Tip: tick Problems > Dispenser in the filter and
 * Search first, so all dispenser problems are on one page.
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
  const table = findTable();
  if (!table) { alert('Could not find the ATM table on this page.'); return; }
  const isPager = tr => !!tr.closest('tfoot') || !!tr.querySelector(PAGER);
  const rows = [...table.rows].filter(tr => !isPager(tr) && !tr.closest('thead') && !tr.querySelector('th') && tr.cells.length >= 6);

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
    const r = icon.getBoundingClientRect();
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

  // DEV / DISP error columns, from the header (fallback: the two cells after REMOTE ADDRESS)
  let errCols = [];
  for (const tr of [...table.rows].filter(r => !isPager(r) && (r.closest('thead') || r.querySelector('th')))) {
    const idx = [...tr.cells].map((c, i) => /^(DEV|DISP)$/i.test(clean(c.innerText)) ? i : -1).filter(i => i >= 0);
    const hasName = [...tr.cells].some(c => /^NAME$/i.test(clean(c.innerText)));
    if (idx.length && hasName) errCols = idx;
  }
  const isErrorIcon = img => !/square|cassette|info/i.test(img.getAttribute('src') || '');

  const results = [], unread = [];
  for (const tr of rows) {
    const cells = [...tr.cells];
    const tidCell = cells.find(td => /^PRV\d+/i.test(clean(td.innerText)));
    if (!tidCell) continue;
    const tid = clean(tidCell.innerText);
    const pid = (tid.match(/\((\d+)\)/) || [])[1] || '';
    const name = clean((cells[cells.indexOf(tidCell) - 1] || {}).innerText);
    // red error icons in the DEV / DISP columns
    const t0 = cells.indexOf(tidCell);
    const iconCells = (errCols.length ? errCols.map(i => cells[i]) : cells.slice(t0 + 2, t0 + 4))
      .filter(td => td && [...td.querySelectorAll('img')].some(isErrorIcon));
    if (!iconCells.length) continue;
    let text = iconCells.map(textInCell).join(' | ');
    if (!DOWN_RE.test(text)) {
      for (const td of iconCells) {
        const t = await hoverText([...td.querySelectorAll('img')].find(isErrorIcon), pid);
        if (t) text += ' | ' + t;
      }
    }
    const readable = /details|dispenser|error|reader|printer|down/i.test(text);
    if (!readable) unread.push(`${tid} ${name}`);
    if (DOWN_RE.test(text)) {
      const box = cells[1] && cells[1].querySelector('input[type=checkbox]');
      if (box && !box.checked) box.click();
      tr.style.outline = '3px solid #ff9800';
      results.push(`${tid}  ${name}${box ? '' : '  (no checkbox found)'}`);
    }
  }

  let msg = results.length
    ? `"Dispenser down" on ${results.length} ATM(s) on this page - their boxes are now TICKED:\n\n${results.join('\n')}\n\n` +
      'Nothing was sent. Check the list, then use Group management and choose the command yourself.'
    : 'No ATM on this page shows "Dispenser down".';
  if (unread.length) {
    msg += `\n\nCould not read the error details of ${unread.length} ATM(s) with a red icon:\n${unread.slice(0, 10).join('\n')}` +
      (unread.length > 10 ? '\n...' : '') + '\nHover one of them and send a photo so this can be fixed.';
  }
  msg += '\n\nOnly this page was checked (tip: filter Problems > Dispenser first).';
  alert(msg);
})();
