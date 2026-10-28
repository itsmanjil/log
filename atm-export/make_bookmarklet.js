// Rebuilds the bookmark files from the scripts (run: node make_bookmarklet.js).
//   atm_export.js           -> bookmarklet.txt
//   find_dispenser_down.js  -> bookmarklet_dispenser_down.txt
// Drops comments and indentation, keeps line breaks, URL-encodes the rest.
const fs = require('fs');
const path = require('path');

for (const [src, out] of [['atm_export.js', 'bookmarklet.txt'], ['find_dispenser_down.js', 'bookmarklet_dispenser_down.txt']]) {
  const code = fs.readFileSync(path.join(__dirname, src), 'utf8')
    .replace(/^\/\*[\s\S]*?\*\/\s*/, '')
    .split(/\r?\n/)
    .filter(line => !/^\s*\/\//.test(line))
    .map(line => line.replace(/\s+\/\/\s.*$/, '').trim())
    .filter(line => line)
    .join('\n');
  fs.writeFileSync(path.join(__dirname, out), 'javascript:' + encodeURIComponent(code) + '\n');
  console.log(`${out}: ${code.length} characters of code`);
}
