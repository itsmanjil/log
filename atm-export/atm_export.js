/*
 * ATM Monitoring -> DAILY ATM STATUS exporter
 * Run it in the browser tab where the ATM Monitoring page is open and you are logged in.
 *   1. Show all ATMs (no filter) and go to page 1 of the table.
 *   2. Press F12 -> Console tab. (The first time, Chrome asks you to type: allow pasting)
 *   3. Paste this whole file and press Enter (or click the bookmark).
 * It downloads ATM_SWITCH_DATA_<date>_<time>.xlsx with two sheets, laid out like
 * copy-pasting the table into DAILY_ATM_STATUS_V3.xlsm (same header rows, same columns):
 *   "Raw Switch Data" - every ATM
 *   "PROBLEM IN ATM"  - the ATMs whose status (STA) dot is red / offline
 * The ImportWebData... macros (Module_WebImport.bas) load them and run the report.
 * If anything looks wrong it downloads ATM_EXPORT_DIAGNOSTIC_<date>_<time>.txt instead
 * (table structure only - no balances, names or addresses).
 */
(async () => {
  const MAX_PAGES = 500;          // safety limit
  const PAGE_TIMEOUT_MS = 20000;  // how long to wait for a page to load
  const PAGER = '.rich-datascr, .dr-dscr, .ui-paginator, [class*="datascr"], [class*="paginator"]';
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const clean = s => (s || '').replace(/\s+/g, ' ').trim();
  const now = new Date();
  const pad = n => String(n).padStart(2, '0');
  const stamp = `${now.getFullYear()}${pad(now.getMonth() + 1)}${pad(now.getDate())}_${pad(now.getHours())}${pad(now.getMinutes())}`;

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

  // STA dot -> 'RED' (offline / problem) or 'GREEN', from its image name, tooltip or
  // class (e.g. SmartVista's /image/atm/open.png "Open"), falling back to the dot's colour.
  const RED_WORDS = ['red', 'offline', 'off', 'down', 'error', 'err', 'fail', 'failed', 'closed', 'close', 'alarm',
    'critical', 'outofservice', 'out', 'disconnected', 'unavailable', 'fault', 'inactive'];
  const GREEN_WORDS = ['green', 'open', 'online', 'on', 'ok', 'up', 'working', 'active', 'inservice'];
  const staIcons = new Set();  // every kind of STA icon seen, for the diagnostic file
  function statusOf(td) {
    const els = [td, ...td.querySelectorAll('*')];
    staIcons.add([...td.querySelectorAll('img')].map(i => `${(i.getAttribute('src') || '').split('/').pop()} ` +
      `"${i.getAttribute('title') || i.getAttribute('alt') || ''}"`).join(' + ') || 'no image');
    const words = new Set(els.flatMap(e => [e.getAttribute('title'), e.getAttribute('alt'), e.getAttribute('src'),
      e.getAttribute('class'), getComputedStyle(e).backgroundImage].join(' ').toLowerCase().split(/[^a-z]+/)));
    if (RED_WORDS.some(w => words.has(w))) return 'RED';
    if (GREEN_WORDS.some(w => words.has(w))) return 'GREEN';
    for (const e of els) {
      const cs = getComputedStyle(e);
      for (const color of [cs.backgroundColor, cs.color, cs.fill]) {
        const m = /rgba?\((\d+), (\d+), (\d+)(?:, ([\d.]+))?\)/.exec(color || '');
        if (!m || m[4] === '0') continue;
        const [r, g, b] = [+m[1], +m[2], +m[3]];
        if (r >= 150 && g <= 110 && b <= 110) return 'RED';
        if (g >= 120 && r <= 120 && b <= 120) return 'GREEN';
      }
    }
    return '';
  }

  const isPagerRow = tr => !!tr.closest('tfoot') || !!tr.querySelector(PAGER);
  const isHeaderRow = tr => !isPagerRow(tr) && (!!tr.closest('thead') || !!tr.querySelector('th'));
  const isDataRow = tr => !isPagerRow(tr) && !tr.closest('thead') && !tr.querySelector('th') && tr.cells.length >= 6;

  // Lay rows out on a grid the way Excel does when you paste a web table: a cell
  // spanning several columns/rows keeps its text in the first one, the rest stay empty.
  function toGrid(rows, valueOf) {
    const grid = rows.map(() => []);
    rows.forEach((tr, ri) => {
      let c = 0;
      for (const td of tr.cells) {
        while (grid[ri][c] !== undefined) c++;
        const cs = Math.max(1, td.colSpan || 1), rs = Math.max(1, td.rowSpan || 1);
        const v = valueOf(td, c);
        for (let dr = 0; dr < rs && ri + dr < rows.length; dr++)
          for (let dc = 0; dc < cs; dc++) grid[ri + dr][c + dc] = dr === 0 && dc === 0 ? v : '';
        c += cs;
      }
    });
    return grid.map(r => Array.from(r, v => v === undefined ? '' : v));
  }

  const readRows = table => toGrid([...table.rows].filter(isDataRow), (td, c) => (c === 0 && statusOf(td)) || cellValue(td));
  const readHeader = table => toGrid([...table.rows].filter(isHeaderRow), td => cellValue(td))
    .filter(r => r.some(v => v));

  const signature = () => {
    const t = findTable();
    if (!t) return '';
    const rows = readRows(t);
    return rows.length ? rows[0].join('~') + '##' + rows[rows.length - 1].join('~') + '#' + rows.length : '';
  };

  // Find the clickable control for page `n`, or a "next" arrow as fallback.
  function findPageControl(n) {
    const pagers = document.querySelectorAll(PAGER + ', [id*="scroller" i], [id*="pager" i]');
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

  // ---------- Column check: same lookups as the macro (Module1 BuildSwitchReportFromRaw) ----------
  // Header text compared on letters/digits only, so odd spaces or hidden characters
  // on the website don't matter; the file then gets the exact names the macro looks for.
  const key = v => String(v || '').toUpperCase().replace(/[^A-Z0-9]/g, '');
  function locateColumns(header) {
    const find = (row, names) => row.findIndex(v => names.includes(key(v)));
    for (let r = 0; r < header.length; r++) {
      const row = header[r];
      const name = find(row, ['NAME']), tid = find(row, ['TIDPID', 'TERMINALID']);
      const disp = find(row, ['DISPENSER', 'IDLETIMELASTUSED']);
      if (name < 0 || tid < 0 || disp < 0 || find(row, ['NPR', 'REMAININGBALANCE']) < 0) continue;
      // FindAvailableBalanceColumn: AVAILABLE BALANCE label (or the label above), else first NPR not under REMAINING
      let avail = -1, firstNpr = -1, freeNpr = -1;
      for (let c = 0; c < row.length && avail < 0; c++) {
        const cat = r > 0 ? key(header[r - 1][c]) : '';
        if (key(row[c]).includes('AVAILABLEBALANCE') || cat.includes('AVAILABLEBALANCE')) avail = c;
        else if (key(row[c]) === 'NPR') {
          if (firstNpr < 0) firstNpr = c;
          if (!cat.includes('REMAINING') && freeNpr < 0) freeNpr = c;
        }
      }
      if (avail < 0) avail = freeNpr >= 0 ? freeNpr : firstNpr;
      return { row: r, name, tid, avail, disp };
    }
    return null;
  }

  // Write the header names exactly as the macro compares them.
  function canonicalHeader(header, cols) {
    const out = header.map(r => r.slice());
    const r = cols.row, names = out[r];
    names[cols.name] = 'NAME'; names[cols.tid] = 'TID (PID)'; names[cols.disp] = 'DISPENSER';
    names.forEach((v, c) => { if (key(v) === 'NPR') names[c] = 'NPR'; });
    if (r > 0) out[r - 1].forEach((v, c) => {
      if (key(v).includes('AVAILABLEBALANCE')) out[r - 1][c] = 'AVAILABLE BALANCE';
      else if (key(v).includes('REMAININGBALANCE')) out[r - 1][c] = 'REMAINING BALANCE';
    });
    if (key(names[cols.avail]) !== 'NPR' && !key(names[cols.avail]).includes('AVAILABLEBALANCE')) names[cols.avail] = 'NPR';
    return out;
  }

  const TID_RE = /^PRV\d+/i;
  const MONEY_RE = /^-?[\d`'’´, ]+(\.\d+)?$/;
  const IDLE_RE = /\b(days?|hours?|hrs?|mins?|minutes?|secs?|seconds?|never)\b/i;
  const BLANK_RE = /^(-+|n\/?a|null|none)$/i;  // placeholders counted as empty
  const pct = x => Math.round(x * 100) + '%';
  function share(data, c, re) {
    const filled = data.map(r => String(r[c] || '')).filter(v => v && !BLANK_RE.test(v));
    return { filled: filled.length / data.length, match: filled.length ? filled.filter(v => re.test(v)).length / filled.length : 0 };
  }
  function checkColumns(cols, data) {
    if (!cols) return ['header row with NAME / TID (PID) / NPR / DISPENSER not found'];
    const problems = [];
    const tid = share(data, cols.tid, TID_RE), name = share(data, cols.name, /./);
    const money = share(data, cols.avail, MONEY_RE), idle = share(data, cols.disp, IDLE_RE);
    const at = c => ` (column ${c + 1}: ${pct(share(data, c, /./).filled)} filled`;
    if (tid.filled < 0.9 || tid.match < 0.9) problems.push(`TID (PID) column does not hold PRV terminal IDs${at(cols.tid)}, ${pct(tid.match)} IDs)`);
    if (name.filled < 0.9 || data.filter(r => TID_RE.test(String(r[cols.name] || ''))).length > data.length * 0.1) problems.push(`NAME column does not hold ATM names${at(cols.name)})`);
    if (money.filled < 0.3 || money.match < 0.9) problems.push(`AVAILABLE BALANCE / NPR column does not hold amounts${at(cols.avail)}, ${pct(money.match)} amounts)`);
    if (idle.filled < 0.5 || idle.match < 0.9) problems.push(`DISPENSER column does not hold idle times${at(cols.disp)}, ${pct(idle.match)} times)`);
    return problems;
  }

  // Fallback when the website's own header rows can't be used: put the header names
  // over the columns whose contents match (terminal IDs, amounts, idle times).
  function headerFromContent(data, width) {
    const score = re => Array.from({ length: width }, (_, c) => {
      const s = share(data, c, re);
      return s.filled >= 0.3 && s.match >= 0.9 ? s.filled : 0;
    });
    const tidScore = score(TID_RE);
    const tid = tidScore.indexOf(Math.max(...tidScore));
    const money = score(MONEY_RE).map((s, c) => s && c > tid ? c : -1).filter(c => c >= 0);
    const idle = score(IDLE_RE).map((s, c) => s && c > tid ? c : -1).filter(c => c >= 0);
    if (tid < 1 || !money.length || !idle.length) return null;
    const groups = Array(width).fill(''), names = Array(width).fill('');
    groups[0] = `FILTERED ${data.length} ATM`;
    names[0] = 'STA'; names[tid - 1] = 'NAME'; names[tid] = 'TID (PID)';
    if (tid + 1 < width) names[tid + 1] = 'REMOTE ADDRESS';
    groups[money[0]] = 'AVAILABLE BALANCE'; names[money[0]] = 'NPR';
    if (money[1] !== undefined) { groups[money[1]] = 'REMAINING BALANCE'; names[money[1]] = 'NPR'; }
    groups[idle[0]] = 'IDLE TIME'; names[idle[0]] = 'DISPENSER';
    if (idle[1] !== undefined) names[idle[1]] = 'CASHIN';
    return [groups, names];
  }

  function download(name, blob) {
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = name;
    document.body.appendChild(a); a.click(); a.remove();
  }

  // Table structure for troubleshooting: tags, spans, classes, image names and
  // header text only - never ATM names, terminal IDs, addresses or balances.
  const showText = v => String(v).replace(/[^\x20-\x7E]/g, ch => '\\u' + ch.charCodeAt(0).toString(16).padStart(4, '0'));
  const notes = [];  // extra findings for the diagnostic file
  function diagnose(table, reason) {
    const shape = td => {
      const t = clean(td.innerText);
      const kind = !t ? 'empty' : TID_RE.test(t) ? 'TID' : MONEY_RE.test(t) ? 'amount' : IDLE_RE.test(t) ? 'time' :
        /^\d+(\.\d+){3}$/.test(t) ? 'ip' : `text(${t.length})`;
      const imgs = [...td.querySelectorAll('img')].map(i => (i.getAttribute('src') || '').split('/').pop());
      return `${td.tagName === 'TH' ? 'TH:' : ''}${kind}${td.colSpan > 1 ? 'x' + td.colSpan : ''}${imgs.length ? '[' + imgs.join(',') + ']' : ''}`;
    };
    const lines = [`ATM EXPORT DIAGNOSTIC ${now.toLocaleString()}`, `Problem: ${reason}`, `Page: ${location.pathname}`];
    if (table) {
      lines.push(`Table id="${table.id}" class="${table.className}" rows=${table.rows.length}`);
      let shown = 0;
      [...table.rows].forEach((tr, i) => {
        const kind = isPagerRow(tr) ? 'PAGER' : isHeaderRow(tr) ? 'HEADER' : isDataRow(tr) ? 'DATA' : 'OTHER';
        if (kind === 'DATA' && shown++ >= 2) return;
        lines.push(`row ${i} ${kind} cells=${tr.cells.length} class="${tr.className}" | ` + (kind === 'HEADER'
          ? [...tr.cells].map(c => `"${clean(c.innerText)}"${c.colSpan > 1 ? 'x' + c.colSpan : ''}${c.rowSpan > 1 ? ' rows' + c.rowSpan : ''}`).join(' ')
          : kind === 'DATA' ? [...tr.cells].map((td, c) => `${c}:${shape(td)}`).join(' ') : ''));
      });
      lines.push(`DATA rows on this page: ${[...table.rows].filter(isDataRow).length}`);
      const sta = [...table.rows].find(isDataRow);
      if (sta) lines.push('STA cell HTML: ' + sta.cells[0].outerHTML.replace(/\s+/g, ' ')
        .replace(/(title|alt)="([^"]{21,})"/g, '$1="(long text)"').slice(0, 600));
    }
    if (staIcons.size) lines.push('STA icons seen: ' + [...staIcons].join(' | '));
    lines.push(...notes);
    download(`ATM_EXPORT_DIAGNOSTIC_${stamp}.txt`, new Blob([lines.join('\r\n')], { type: 'text/plain' }));
    alert(`${reason}\n\nNothing was exported. A file ATM_EXPORT_DIAGNOSTIC_${stamp}.txt was saved in Downloads ` +
          '(table layout only, no ATM data). Send a photo of it so the script can be fixed.');
  }

  // ---------- Read every page ----------
  const table = findTable();
  if (!table) { alert('Could not find the data table on this page.'); return; }
  const websiteHeader = readHeader(table);

  const seen = new Set();
  const all = [];
  const add = rows => {
    let added = 0;
    for (const r of rows) {
      const rowKey = r.join('~');
      if (!seen.has(rowKey)) { seen.add(rowKey); all.push(r); added++; }
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

  if (!all.length) { diagnose(findTable(), 'No ATM rows found.'); return; }

  // ---------- Header rows: the website's own, else rebuilt from the cell contents ----------
  const lastHeader = readHeader(findTable());
  const width = Math.max(...all.map(r => r.length), ...websiteHeader.map(r => r.length), ...lastHeader.map(r => r.length));
  const fit = r => Array.from({ length: width }, (_, i) => r[i] === undefined ? '' : r[i]);
  const data = all.map(fit);
  const candidates = [['website header', websiteHeader], ['website header (last page)', lastHeader], ['columns detected from the data', headerFromContent(data, width)]];
  let header = null, headerSource = '', problems = [];
  for (const [source, rows] of candidates) {
    const h = rows ? rows.map(fit) : null;
    const p = h ? checkColumns(locateColumns(h), data) : ['could not detect the columns'];
    notes.push(`Check "${source}": ${p.length ? p.join('; ') : 'OK'}`);
    if (h) h.forEach((r, i) => notes.push(`    ${source} row ${i}: ${r.map(v => `"${showText(v)}"`).join(' ')}`));
    if (!p.length) { header = h; headerSource = source; break; }
    if (!problems.length) problems = p;
  }
  notes.push(`ATMs read: ${data.length} from ${page} page(s), row widths: ${[...new Set(all.map(r => r.length))].join(',')}`);
  if (!header) { diagnose(findTable(), 'The table columns are not what the report expects: ' + problems.join('; ') + '.'); return; }
  header = canonicalHeader(header, locateColumns(header));
  const cols = locateColumns(header);
  console.log(`Columns (${headerSource}): NAME=${cols.name + 1} TID=${cols.tid + 1} NPR=${cols.avail + 1} DISPENSER=${cols.disp + 1} of ${width}`);

  const red = data.filter(r => r[0] === 'RED');
  const unknown = data.filter(r => r[0] !== 'RED' && r[0] !== 'GREEN').length;
  if (unknown) {
    diagnose(findTable(), `Could not read the red/green status dot of ${unknown} of ${data.length} ATMs, so the PROBLEM IN ATM list would be wrong.`);
    return;
  }

  // ---------- Build the .xlsx file (no external libraries) ----------
  const xmlEsc = v => String(v).replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '')
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const colName = i => { let s = ''; for (i++; i > 0; i = Math.floor((i - 1) / 26)) s = String.fromCharCode(65 + (i - 1) % 26) + s; return s; };

  // Every value is written as text, exactly as the website shows it (e.g. 1`065`000.00),
  // the same as copy-paste; the macro's CleanNprValue converts the balances itself.
  const sheetXml = rowsData => {
    const rows = [...header, ...rowsData];
    const h = header.length;
    const xmlRows = rows.map((r, ri) => `<row r="${ri + 1}">` + r.map((v, ci) => v
      ? `<c r="${colName(ci)}${ri + 1}"${ri < h ? ' s="1"' : ''} t="inlineStr"><is><t xml:space="preserve">${xmlEsc(v)}</t></is></c>`
      : '').join('') + '</row>').join('');
    const colWidths = Array.from({ length: width }, (_, i) => Math.min(40, Math.max(6, ...rows.slice(h - 1).map(r => String(r[i] || '').length + 2))));
    return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">' +
      `<dimension ref="A1:${colName(width - 1)}${rows.length}"/>` +
      `<sheetViews><sheetView workbookViewId="0"><pane ySplit="${h}" topLeftCell="A${h + 1}" activePane="bottomLeft" state="frozen"/>` +
      `<selection pane="bottomLeft" activeCell="A${h + 1}" sqref="A${h + 1}"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight="15"/>` +
      `<cols>${colWidths.map((w, i) => `<col min="${i + 1}" max="${i + 1}" width="${w}" customWidth="1"/>`).join('')}</cols>` +
      `<sheetData>${xmlRows}</sheetData>` +
      '<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/></worksheet>';
  };

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
      '<workbookPr/><bookViews><workbookView activeTab="0"/></bookViews>' +
      '<sheets><sheet name="Raw Switch Data" sheetId="1" r:id="rId1"/><sheet name="PROBLEM IN ATM" sheetId="2" r:id="rId2"/></sheets>' +
      '<calcPr calcId="191029"/></workbook>',
    'xl/_rels/workbook.xml.rels': '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>' +
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">' +
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>' +
      '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>' +
      '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
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
    'xl/worksheets/sheet1.xml': sheetXml(data),
    'xl/worksheets/sheet2.xml': sheetXml(red),
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
    const nameB = enc.encode(name), bytes = enc.encode(text), crc = crc32(bytes);
    const head = (sig, extra) => {
      const h = new DataView(new ArrayBuffer(extra ? 46 : 30));
      let p = 0; const u32 = v => { h.setUint32(p, v, true); p += 4; }, u16 = v => { h.setUint16(p, v, true); p += 2; };
      u32(sig); if (extra) u16(20); u16(20); u16(0); u16(0); u16(dosTime); u16(dosDate);
      u32(crc); u32(bytes.length); u32(bytes.length); u16(nameB.length); u16(0);
      if (extra) { u16(0); u16(0); u16(0); u32(0); u32(offset); }
      return new Uint8Array(h.buffer);
    };
    const local = head(0x04034b50, false);
    central.push(head(0x02014b50, true), nameB);
    parts.push(local, nameB, bytes);
    offset += local.length + nameB.length + bytes.length;
  }
  const cdSize = central.reduce((s, b) => s + b.length, 0);
  const end = new DataView(new ArrayBuffer(22));
  end.setUint32(0, 0x06054b50, true); end.setUint16(8, Object.keys(files).length, true);
  end.setUint16(10, Object.keys(files).length, true); end.setUint32(12, cdSize, true); end.setUint32(16, offset, true);
  const fileName = `ATM_SWITCH_DATA_${stamp}.xlsx`;
  download(fileName, new Blob([...parts, ...central, new Uint8Array(end.buffer)],
    { type: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' }));
  console.log(`Done: ${data.length} ATMs, ${red.length} red, from ${page} page(s) -> ${fileName}`);
  alert(`Exported ${data.length} ATMs from ${page} page(s).\n` +
        `Raw Switch Data: ${data.length} ATMs\nPROBLEM IN ATM: ${red.length} red/offline ATMs\n\nFile: ${fileName}`);
})();
