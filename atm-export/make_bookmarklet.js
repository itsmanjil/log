// Rebuilds bookmarklet.txt from atm_export.js (run: node make_bookmarklet.js).
// Drops comments and indentation, keeps line breaks, URL-encodes the rest.
const fs = require('fs');
const path = require('path');

const src = fs.readFileSync(path.join(__dirname, 'atm_export.js'), 'utf8');
const code = src
  .replace(/^\/\*[\s\S]*?\*\/\s*/, '')
  .split(/\r?\n/)
  .filter(line => !/^\s*\/\//.test(line))
  .map(line => line.replace(/\s+\/\/\s.*$/, '').trim())
  .filter(line => line)
  .join('\n');
fs.writeFileSync(path.join(__dirname, 'bookmarklet.txt'), 'javascript:' + encodeURIComponent(code) + '\n');
console.log(`bookmarklet.txt: ${code.length} characters of code`);
