/*
 * ATM Monitoring -> Excel (.xlsx) exporter for the downtime report
 * Run it in the browser tab where the ATM Monitoring page is open and you are logged in.
 *   1. Go to page 1 of the table (set any filter you want first).
 *   2. Press F12 -> Console tab. (The first time, Chrome asks you to type: allow pasting)
 *   3. Paste this whole file and press Enter.
 * It goes through every page and downloads ATM_Downtime_Report_<date>.xlsx with two sheets:
 *   "ATM Status" - every ATM, down/offline rows highlighted red, filters + frozen header
 *   "Summary"    - totals (ATMs exported, down, up) and counts per status
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

  // ---------- Build the .xlsx file (no external libraries) ----------
  const now = new Date();
  const pad = n => String(n).padStart(2, '0');
  const stamp = `${now.getFullYear()}-${pad(now.getMonth() + 1)}-${pad(now.getDate())} ${pad(now.getHours())}:${pad(now.getMinutes())}`;
  const xmlEsc = v => String(v).replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const colName = i => { let s = ''; for (i++; i > 0; i = Math.floor((i - 1) / 26)) s = String.fromCharCode(65 + (i - 1) % 26) + s; return s; };
  // "1'065'000.00", "1,065,000.00", "17" -> numbers; IPs, IDs and text stay text
  const toNumber = v => /^-?\d{1,3}(['’, ]?\d{3})*(\.\d+)?$/.test(v) ? Number(v.replace(/['’, ]/g, '')) : null;
  const isDown = r => /\b(red|offline|down|closed|out of service)\b/i.test(r[0] || '');

  // Styles: 0 normal, 1 header, 2 down-row text, 3 title, 4 number, 5 down-row number
  const cell = (ref, v, style, down) => {
    const n = toNumber(v || '');
    if (n !== null) return `<c r="${ref}" s="${down ? 5 : 4}"><v>${n}</v></c>`;
    const s = style ?? (down ? 2 : 0);
    return v ? `<c r="${ref}" s="${s}" t="inlineStr"><is><t xml:space="preserve">${xmlEsc(v)}</t></is></c>` : (s ? `<c r="${ref}" s="${s}"/>` : '');
  };
  const sheetXml = (rows, { title, header, filter, widths }) => {
    const lastCol = colName(Math.max(...rows.map(r => r.length), 1) - 1);
    const xmlRows = rows.map((r, ri) => {
      const rn = ri + 1;
      const down = header && ri >= 2 && isDown(r);
      const style = ri === 0 && title ? 3 : (ri === 1 && header ? 1 : undefined);
      return `<row r="${rn}">${r.map((v, ci) => cell(colName(ci) + rn, v, style, down)).join('')}</row>`;
    }).join('');
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
      (header ? '<sheetViews><sheetView workbookViewId="0"><pane ySplit="2" topLeftCell="A3" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>' : '') +
      `<cols>${widths.map((w, i) => `<col min="${i + 1}" max="${i + 1}" width="${w}" customWidth="1"/>`).join('')}</cols>` +
      `<sheetData>${xmlRows}</sheetData>` +
      (filter ? `<autoFilter ref="A2:${lastCol}${rows.length}"/>` : '') +
      '</worksheet>';
  };
  const widthsFor = rows => Array.from({ length: Math.max(...rows.map(r => r.length)) }, (_, i) =>
    Math.min(60, Math.max(6, ...rows.slice(1).map(r => String(r[i] || '').length + 2))));

  const dataRows = [[`ATM Monitoring export - ${stamp}`], headers, ...all];

  const statusCounts = {};
  for (const r of all) { const k = r[0] || '(blank)'; statusCounts[k] = (statusCounts[k] || 0) + 1; }
  const downCount = all.filter(isDown).length;
  const summaryRows = [
    [`ATM Status Summary - ${stamp}`],
    ['Item', 'Value'],
    ['Total ATMs exported', String(all.length)],
    ['ATMs down / offline (highlighted red)', String(downCount)],
    ['ATMs up', String(all.length - downCount)],
    ['Pages read', String(page)],
    ['Source page', location.href],
    [],
    [`Status column (${headers[0]})`, 'Count'],
    ...Object.entries(statusCounts).sort((a, b) => b[1] - a[1]).map(([k, n]) => [k, String(n)]),
  ];

  const stylesXml = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
    '<numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0.00"/></numFmts>' +
    '<fonts count="3"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="14"/><name val="Calibri"/></font></fonts>' +
    '<fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill>' +
    '<fill><patternFill patternType="solid"><fgColor rgb="FFD9E1F2"/><bgColor indexed="64"/></patternFill></fill>' +
    '<fill><patternFill patternType="solid"><fgColor rgb="FFF8CBAD"/><bgColor indexed="64"/></patternFill></fill></fills>' +
    '<borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border>' +
    '<border><left style="thin"><color rgb="FFBFBFBF"/></left><right style="thin"><color rgb="FFBFBFBF"/></right><top style="thin"><color rgb="FFBFBFBF"/></top><bottom style="thin"><color rgb="FFBFBFBF"/></bottom><diagonal/></border></borders>' +
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>' +
    '<cellXfs count="6">' +
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyBorder="1"/>' +
    '<xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1"/>' +
    '<xf numFmtId="0" fontId="0" fillId="3" borderId="1" xfId="0" applyFill="1" applyBorder="1"/>' +
    '<xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1"/>' +
    '<xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyBorder="1"/>' +
    '<xf numFmtId="164" fontId="0" fillId="3" borderId="1" xfId="0" applyNumberFormat="1" applyFill="1" applyBorder="1"/>' +
    '</cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>';

  const files = {
    '[Content_Types].xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">' +
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>' +
      '<Default Extension="xml" ContentType="application/xml"/>' +
      '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>' +
      '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' +
      '<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>' +
      '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>',
    '_rels/.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
    'xl/workbook.xml': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">' +
      '<sheets><sheet name="ATM Status" sheetId="1" r:id="rId1"/><sheet name="Summary" sheetId="2" r:id="rId2"/></sheets>' +
      '<definedNames><definedName name="_xlnm._FilterDatabase" localSheetId="0" hidden="1">' +
      `'ATM Status'!$A$2:$${colName(width - 1)}$${all.length + 2}</definedName></definedNames></workbook>`,
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>' +
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>' +
      '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
    'xl/styles.xml': stylesXml,
    'xl/worksheets/sheet1.xml': sheetXml(dataRows, { title: true, header: true, filter: true, widths: widthsFor(dataRows) }),
    'xl/worksheets/sheet2.xml': sheetXml(summaryRows, { title: true, header: true, filter: false, widths: [45, 20] }),
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
      u32(sig); if (extra) u16(20); u16(20); u16(0x0800); u16(0); u16(dosTime); u16(dosDate);
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
  a.download = `ATM_Downtime_Report_${stamp.replace(/[-: ]/g, '').replace(/^(\d{8})/, '$1_')}.xlsx`;
  document.body.appendChild(a); a.click(); a.remove();
  console.log(`Done: ${all.length} rows (${downCount} down) from ${page} page(s) -> ${a.download}`);
  alert(`Exported ${all.length} ATMs (${downCount} down/offline) from ${page} page(s).\nFile: ${a.download}`);
})();
