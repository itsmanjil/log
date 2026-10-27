/*
 * ATM Monitoring -> CSV exporter
 * Run it in the browser tab where the ATM Monitoring page is open and you are logged in.
 *   1. Go to page 1 of the table (set any filter you want first).
 *   2. Press F12 -> Console tab. (The first time, Chrome asks you to type: allow pasting)
 *   3. Paste this whole file and press Enter.
 * It goes through every page and downloads atm_monitoring_<date>.csv (opens in Excel).
 */
(async () => {
  const MAX_PAGES = 500;          // safety limit
  const PAGE_TIMEOUT_MS = 20000;  // how long to wait for a page to load
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const clean = s => (s || '').replace(/\s+/g, ' ').trim();

  // The data table is the one with the most wide rows (nested tables are skipped by t.rows).
  function findTable() {
    let best = null, bestN = 0;
    for (const t of document.querySelectorAll('table')) {
      const n = [...t.rows].filter(r => r.cells.length >= 6).length;
      if (n > bestN) { best = t; bestN = n; }
    }
    return best;
  }

  // Cell value = visible text + tooltip/alt text of icons (status dots, cassette icons, etc.).
  function cellValue(td) {
    const parts = [];
    const txt = clean(td.innerText);
    if (txt) parts.push(txt);
    for (const el of [td, ...td.querySelectorAll('img, [title], [alt]')]) {
      const t = el.getAttribute('title') || el.getAttribute('alt');
      if (t) parts.push(clean(t));
      else if (el.tagName === 'IMG' && el.src) parts.push(el.src.split('/').pop().split('?')[0].replace(/\.\w+$/, ''));
    }
    return [...new Set(parts)].join(' | ');
  }

  function isPagerRow(tr) {
    return !!tr.closest('tfoot') || !!tr.querySelector('.rich-datascr, .dr-dscr, .ui-paginator, [class*="datascr"], [class*="paginator"]');
  }

  function readHeaders(table) {
    const hr = (table.tHead && table.tHead.rows[table.tHead.rows.length - 1]) ||
               [...table.rows].find(r => r.querySelector('th'));
    return hr ? [...hr.cells].map(c => clean(c.innerText) || clean(c.title)) : [];
  }

  function readRows(table) {
    return [...table.rows]
      .filter(r => !r.closest('thead') && !r.querySelector('th') && !isPagerRow(r) && r.cells.length >= 6)
      .map(r => [...r.cells].map(cellValue));
  }

  const signature = () => {
    const t = findTable();
    if (!t) return '';
    const rows = readRows(t);
    return rows.length ? rows[0].join('~') + '##' + rows[rows.length - 1].join('~') + '#' + rows.length : '';
  };

  // Find the clickable control for page `n`, or a "next" arrow as fallback.
  function findPageControl(n) {
    const pagers = document.querySelectorAll('.rich-datascr, .dr-dscr, .ui-paginator, [class*="datascr"], [class*="paginator"], [id*="scroller" i], [id*="pager" i]');
    const scopes = pagers.length ? [...pagers] : [document.body];
    for (const scope of scopes) {
      const els = [...scope.querySelectorAll('td, a, span, button, li')];
      const num = els.find(e => clean(e.innerText) === String(n) && e.children.length === 0);
      if (num) return num;
    }
    for (const scope of scopes) {
      const els = [...scope.querySelectorAll('td, a, span, button, li')];
      const next = els.find(e => {
        const t = clean(e.innerText).toLowerCase();
        const cls = (e.className || '').toString().toLowerCase();
        const disabled = /dis|inact-btn|ui-state-disabled/.test(cls);
        return !disabled && (['›', '»', '>', '>>', 'next', 'fastforward'].includes(t) || /(^|[-_ ])next/.test(cls) ||
               (e.getAttribute('onclick') || '').includes("'next'") || (e.getAttribute('onclick') || '').includes("'fastforward'"));
      });
      if (next) return next;
    }
    return null;
  }

  async function waitForChange(oldSig) {
    const start = Date.now();
    while (Date.now() - start < PAGE_TIMEOUT_MS) {
      await sleep(300);
      const s = signature();
      if (s && s !== oldSig) { await sleep(400); return true; }
    }
    return false;
  }

  const table = findTable();
  if (!table) { alert('Could not find the data table on this page.'); return; }
  let headers = readHeaders(table);

  const seen = new Set();
  const all = [];
  const add = rows => {
    let added = 0;
    for (const r of rows) {
      const key = r.join('~');
      if (!seen.has(key)) { seen.add(key); all.push(r); added++; }
    }
    return added;
  };

  let page = 1;
  console.log(`Page 1: ${add(readRows(table))} rows`);
  while (page < MAX_PAGES) {
    const ctl = findPageControl(page + 1);
    if (!ctl) break;
    const before = signature();
    ctl.click();
    if (!(await waitForChange(before))) { console.log('No more pages (table did not change).'); break; }
    page++;
    const added = add(readRows(findTable()));
    console.log(`Page ${page}: ${added} new rows`);
    if (added === 0) break; // landed on a page we already have -> finished
  }

  const width = Math.max(headers.length, ...all.map(r => r.length));
  headers = Array.from({ length: width }, (_, i) => headers[i] || `Col${i + 1}`);
  const esc = v => /[",\n;]/.test(v) ? `"${v.replace(/"/g, '""')}"` : v;
  const csv = [headers, ...all].map(r => r.map(v => esc(v || '')).join(',')).join('\r\n');

  const ts = new Date().toISOString().slice(0, 16).replace(/[-:T]/g, '');
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob(['﻿' + csv], { type: 'text/csv;charset=utf-8' }));
  a.download = `atm_monitoring_${ts}.csv`;
  document.body.appendChild(a); a.click(); a.remove();
  console.log(`Done: ${all.length} rows from ${page} page(s) -> ${a.download}`);
  alert(`Exported ${all.length} rows from ${page} page(s).`);
})();
