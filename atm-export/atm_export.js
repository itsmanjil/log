/*
 * ATM Monitoring -> DAILY ATM STATUS exporter
 * Run it in the browser tab where the ATM Monitoring page is open and you are logged in.
 *   1. Set the website filter for the list you need and go to page 1 of the table.
 *   2. Press F12 -> Console tab. (The first time, Chrome asks you to type: allow pasting)
 *   3. Paste this whole file and press Enter (or click the bookmark), then pick the list:
 *        1 = all ATMs      -> downloads ATM_RAW_SWITCH_DATA_<date>.xlsx
 *        2 = problem ATMs  -> downloads ATM_PROBLEM_IN_ATM_<date>.xlsx
 * Both files use the same 16-column layout as copy-pasting the table into the
 * "Raw Switch Data" / "PROBLEM IN ATM" sheets of DAILY_ATM_STATUS_V3.xlsm.
 * The ImportWebData... macros (Module_WebImport.bas) load them and run the report.
 */
(async () => {
  const LISTS = {
    '1': { sheet: 'Raw Switch Data', file: 'ATM_RAW_SWITCH_DATA' },
    '2': { sheet: 'PROBLEM IN ATM', file: 'ATM_PROBLEM_IN_ATM' },
  };
  const choice = prompt('Which list is on screen?\n\n1 = ALL ATMs  (Raw Switch Data)\n2 = PROBLEM ATMs  (PROBLEM IN ATM)', '1');
  if (choice === null) return;
  const list = LISTS[choice.trim()];
  if (!list) { alert('Please enter 1 or 2.'); return; }

  // Same two header rows as the website table pasted into DAILY_ATM_STATUS_V3.
  // The macro finds columns by these names (NAME, TID (PID), NPR under AVAILABLE BALANCE, DISPENSER).
  const GROUP_ROW = ['', '', '', '', '', 'PROBLEMS', '', 'CASSETTES', '', '', '', '', 'AVAILABLE BALANCE', 'REMAINING BALANCE', 'IDLE TIME', ''];
  const HEADER_ROW = ['STA', '', 'NAME', 'TID (PID)', 'REMOTE ADDRESS', 'DEV', 'DISP', '', '', '', 'REJ', 'CASHIN', 'NPR', 'NPR', 'DISPENSER', 'CASHIN'];

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

  // Cell value = visible text, like copy-paste gives. Cells with only an icon
  // (status dot, error icons) get the icon's tooltip/alt/image name instead.
  function cellValue(td) {
    const txt = clean(td.innerText);
    if (txt) return txt;
    const parts = [];
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

  if (!all.length) { alert('No ATM rows found.'); return; }
  const wrongWidth = all.filter(r => r.length !== HEADER_ROW.length).length;
  if (wrongWidth) {
    alert(`Warning: ${wrongWidth} of ${all.length} rows do not have ${HEADER_ROW.length} columns.\n` +
          'The website layout may have changed - check the file before running the report.');
  }
  const rows = [[`FILTERED ${all.length} ATM`, ...GROUP_ROW.slice(1)], HEADER_ROW, ...all];

  // ---------- Build the .xlsx file (no external libraries) ----------
  const now = new Date();
  const pad = n => String(n).padStart(2, '0');
  const xmlEsc = v => String(v).replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const colName = i => { let s = ''; for (i++; i > 0; i = Math.floor((i - 1) / 26)) s = String.fromCharCode(65 + (i - 1) % 26) + s; return s; };
  const lastCol = colName(Math.max(...rows.map(r => r.length)) - 1);

  // Every value is written as text, exactly as the website shows it (e.g. 1`065`000.00),
  // the same as copy-paste; the macro's CleanNprValue converts the balances itself.
  const xmlRows = rows.map((r, ri) => `<row r="${ri + 1}">` + r.map((v, ci) => v
    ? `<c r="${colName(ci)}${ri + 1}"${ri < 2 ? ' s="1"' : ''} t="inlineStr"><is><t xml:space="preserve">${xmlEsc(v)}</t></is></c>`
    : '').join('') + '</row>').join('');
  const colWidths = HEADER_ROW.map((_, i) => Math.min(40, Math.max(6, ...rows.slice(1).map(r => String(r[i] || '').length + 2))));
  const sheetXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
    `<dimension ref="A1:${lastCol}${rows.length}"/>` +
    '<sheetViews><sheetView workbookViewId="0"><pane ySplit="2" topLeftCell="A3" activePane="bottomLeft" state="frozen"/>' +
    '<selection pane="bottomLeft" activeCell="A3" sqref="A3"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight="15"/>' +
    `<cols>${colWidths.map((w, i) => `<col min="${i + 1}" max="${i + 1}" width="${w}" customWidth="1"/>`).join('')}</cols>` +
    `<sheetData>${xmlRows}</sheetData>` +
    '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/></worksheet>';

  const files = {
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
      '<Default Extension="xml" ContentType="application/xml"/>' +
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' +
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' +
      '<workbookPr/><bookViews><workbookView activeTab="0"/></bookViews>' +
      `<sheets><sheet name="${list.sheet}" sheetId="1" r:id="rId1"/></sheets><calcPr calcId="191029"/></workbook>`,
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>' +
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
    'xl/styles.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
      '<fonts count="2"><font><sz val="10"/><name val="Calibri"/></font><font><b/><sz val="10"/><name val="Calibri"/></font></fonts>' +
      '<fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>' +
      '<fill><patternFill patternType="solid"><fgColor rgb="FFD9E1F2"/><bgColor indexed="64"/></patternFill></fill></fills>' +
      '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>' +
      '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' +
      '<cellXfs count="2"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>' +
      '<xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyFont="1" applyFill="1"/></cellXfs>' +
      '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>',
    'xl/worksheets/sheet1.xml': sheetXml,
  };

  // Minimal ZIP writer (stored, no compression) - an .xlsx is just a zip of these XML files
  const crcTable = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xEDB88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
  const crc32 = b => { let c = 0xFFFFFFFF; for (let i = 0; i < b.length; i++) c = crcTable[(c ^ b[i]) & 0xFF] ^ (c >>> 8); return (c ^ 0xFFFFFFFF) >>> 0; };
  const enc = new TextEncoder();
  const dosTime = (now.getHours() << 11) | (now.getMinutes() << 5) | (now.getSeconds() >> 1);
  const dosDate = ((now.getFullYear() - 1980) << 9) | ((now.getMonth() + 1) << 5) | now.getDate();
  const parts = [], central = [];
  let offset = 0;
  for (const [name, text] of Object.entries(files)) {
    const nameB = enc.encode(name), data = enc.encode(text), crc = crc32(data);
    const head = (sig, extra) => {
      const h = new DataView(new ArrayBuffer(extra ? 46 : 30));
      let p = 0; const u32 = v => { h.setUint32(p, v, true); p += 4; }, u16 = v => { h.setUint16(p, v, true); p += 2; };
      u32(sig); if (extra) u16(20); u16(20); u16(0); u16(0); u16(dosTime); u16(dosDate);
      u32(crc); u32(data.length); u32(data.length); u16(nameB.length); u16(0);
      if (extra) { u16(0); u16(0); u16(0); u32(0); u32(offset); }
      return new Uint8Array(h.buffer);
    };
    const local = head(0x04034b50, false);
    central.push(head(0x02014b50, true), nameB);
    parts.push(local, nameB, data);
    offset += local.length + nameB.length + data.length;
  }
  const cdSize = central.reduce((s, b) => s + b.length, 0);
  const end = new DataView(new ArrayBuffer(22));
  end.setUint32(0, 0x06054b50, true); end.setUint16(8, Object.keys(files).length, true);
  end.setUint16(10, Object.keys(files).length, true); end.setUint32(12, cdSize, true); end.setUint32(16, offset, true);
  const blob = new Blob([...parts, ...central, new Uint8Array(end.buffer)],
    { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' });

  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `${list.file}_${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}_${pad(now.getHours())}${pad(now.getMinutes())}.xlsx`;
  document.body.appendChild(a); a.click(); a.remove();
  console.log(`Done: ${all.length} ATMs from ${page} page(s) -> ${a.download}`);
  alert(`Exported ${all.length} ATMs from ${page} page(s) for "${list.sheet}".\nFile: ${a.download}`);
})();
