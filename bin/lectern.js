#!/usr/bin/env node
// Lectern: present HTML or image slide decks with a presenter view.
//   lectern                 open your library (~/Lectern) where you add decks
//   lectern <folder|file>   present that deck directly
// Options: --port 4321  --no-open
import http from 'node:http';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';

const APP_DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), '..', 'app');
const args = process.argv.slice(2);
if (args.includes('-h') || args.includes('--help')) {
  console.log('Usage: lectern [deck folder or .html file] [--port 4321] [--no-open]\n       lectern export <deck folder>   add a presenter view to a deck website');
  process.exit(0);
}
// lectern export <deck folder>: copy the presenter into the deck, so the deck's own website
// (for example on Vercel) has a presenter view at /presenter/. No server needed there.
if (args[0] === 'export') {
  const dir = path.resolve(args[1] || '.');
  if (!fs.existsSync(dir) || !fs.statSync(dir).isDirectory()) { console.error(`Not a folder: ${dir}`); process.exit(1); }
  const out = path.join(dir, 'presenter');
  fs.mkdirSync(out, { recursive: true });
  fs.copyFileSync(path.join(APP_DIR, 'presenter.html'), path.join(out, 'index.html'));
  fs.copyFileSync(path.join(APP_DIR, 'audience.html'), path.join(out, 'audience.html'));
  fs.copyFileSync(path.join(APP_DIR, 'adapter.js'), path.join(out, 'adapter.js'));
  console.log(`Added the presenter to ${out}. Publish the deck, then open <your site>/presenter/`);
  process.exit(0);
}
const portArg = args.indexOf('--port');
let port = portArg >= 0 ? Number(args[portArg + 1]) : 4321;
const noOpen = args.includes('--no-open');
const target = args.find((a, i) => !a.startsWith('--') && i !== portArg + 1);

// ---------- decks ----------
// Library mode: every folder in ~/Lectern is a deck. Direct mode: one deck, from the command line.
const LIBRARY = process.env.LECTERN_HOME || path.join(os.homedir(), 'Lectern');
const direct = new Map(); // name -> { dir, file }
if (target) {
  const abs = path.resolve(target);
  if (!fs.existsSync(abs)) { console.error(`Not found: ${abs}`); process.exit(1); }
  const isDir = fs.statSync(abs).isDirectory();
  direct.set(path.basename(isDir ? abs : path.dirname(abs)), { dir: isDir ? abs : path.dirname(abs), file: isDir ? null : path.basename(abs) });
} else {
  fs.mkdirSync(LIBRARY, { recursive: true });
}

const IMAGE_RE = /\.(png|jpe?g|gif|webp|avif|svg)$/i;
const naturally = (a, b) => a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' });
const safeName = n => typeof n === 'string' && /^[^/\\]+$/.test(n) && !n.startsWith('.');

// A library entry is a folder, or a link to one HTML file (an imported file).
function linkedFile(name) {
  if (direct.size) { const d = direct.get(name); return d?.file ? path.join(d.dir, d.file) : null; }
  if (!safeName(name)) return null;
  try {
    const real = fs.realpathSync(path.join(LIBRARY, name));
    return fs.statSync(real).isFile() && /\.html?$/i.test(real) ? real : null;
  } catch { return null; }
}
function deckDir(name) {
  if (direct.size) return direct.get(name)?.dir || null;
  if (!safeName(name)) return null;
  const file = linkedFile(name);
  if (file) return path.dirname(file);
  const dir = path.join(LIBRARY, name);
  return fs.existsSync(dir) && fs.statSync(dir).isDirectory() ? dir : null;
}
function listDecks() {
  if (direct.size) return [...direct.keys()];
  // deckDir follows links, so linked folders and imported files count too.
  return fs.readdirSync(LIBRARY).filter(n => !n.startsWith('.') && deckDir(n)).sort(naturally);
}
// What to show for a deck: its HTML page, or a page we build from its images.
function deckEntry(name) {
  const dir = deckDir(name);
  if (!dir) return null;
  const file = linkedFile(name);
  if (file) return { html: path.basename(file) };
  const files = fs.readdirSync(dir).filter(f => !f.startsWith('.'));
  const htmls = files.filter(f => /\.html?$/i.test(f));
  if (htmls.length) return { html: htmls.includes('index.html') ? 'index.html' : htmls.sort(naturally)[0] };
  let images = files.filter(f => IMAGE_RE.test(f)).sort(naturally);
  // slides.txt (one file name per line) sets the order, after a reorder.
  try {
    const listed = fs.readFileSync(path.join(dir, 'slides.txt'), 'utf8').split('\n').map(l => l.trim()).filter(l => images.includes(l));
    images = [...listed, ...images.filter(f => !listed.includes(f))];
  } catch {}
  return images.length ? { images } : null;
}
function imageDeckHtml(name, images) {
  const esc = s => s.replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
  return `<!doctype html><html><head><meta charset="utf-8"><title>${esc(name)}</title><style>
html,body{margin:0;height:100%;background:#000;overflow:hidden}
section{position:fixed;inset:0;display:none}section.active{display:block}
img{width:100%;height:100%;object-fit:contain}</style></head><body>
${images.map((f, i) => `<section class="slide${i ? '' : ' active'}"><img src="${encodeURIComponent(f)}" alt="${esc(f)}"></section>`).join('\n')}
<script>
const s=[...document.querySelectorAll('section')];let i=0;
const go=n=>{s[i].classList.remove('active');i=Math.max(0,Math.min(s.length-1,n));s[i].classList.add('active')};
addEventListener('keydown',e=>{
  if(['ArrowRight','ArrowDown','PageDown',' ','Enter'].includes(e.key))go(i+1);
  else if(['ArrowLeft','ArrowUp','PageUp','Backspace'].includes(e.key))go(i-1);
  else if(e.key==='Home')go(0);else if(e.key==='End')go(s.length-1);
});
</script></body></html>`;
}

// ---------- notes.md ----------
// One file per deck that people and AI agents can both read and edit:
//   ## Slide 3 · How are you really doing?
//   The note text...
const NOTES_HEADER = `<!-- Speaker notes for Lectern. There is one section per slide, in slide order.
Write the notes for a slide under its heading. Keep "## Slide N" at the start of each heading:
Lectern uses the number to match notes to slides. The text after the dot is only a label.
A note here wins over a note written inside the deck's HTML (<aside class="notes"> or data-notes).
Lectern shows changes to this file in the presenter view within a few seconds. -->`;
const HEADING_RE = /^## Slide (\d+)\b.*$/gm;

// A folder deck keeps notes in notes.md. An imported HTML file keeps them in <file name>.notes.md beside it.
function notesPath(name) {
  const file = linkedFile(name);
  return file ? file.replace(/\.html?$/i, '.notes.md') : path.join(deckDir(name), 'notes.md');
}
function readNotes(name) {
  let text;
  try { text = fs.readFileSync(notesPath(name), 'utf8'); } catch { return { notes: {}, labels: {} }; }
  const notes = {}, labels = {};
  const marks = [...text.matchAll(HEADING_RE)];
  marks.forEach((m, i) => {
    const end = i + 1 < marks.length ? marks[i + 1].index : text.length;
    notes[m[1]] = text.slice(m.index + m[0].length, end).trim();
    labels[m[1]] = m[0].replace(/^## Slide \d+\s*·?\s*/, '');
  });
  return { notes, labels };
}
function writeNotes(name, notes, labels, count, title) {
  const n = Math.max(count || 0, ...Object.keys(notes).map(Number), 0);
  let out = `# Speaker notes${title ? ': ' + title : ''}\n\n${NOTES_HEADER}\n`;
  for (let i = 1; i <= n; i++) {
    const label = (labels[i] || '').replace(/\s+/g, ' ').trim();
    out += `\n## Slide ${i}${label ? ' · ' + label : ''}\n\n${notes[i] ? notes[i] + '\n' : ''}`;
  }
  fs.writeFileSync(notesPath(name), out);
}

// ---------- http ----------
const TYPES = {
  '.html': 'text/html; charset=utf-8', '.htm': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript',
  '.mjs': 'text/javascript', '.json': 'application/json', '.svg': 'image/svg+xml', '.png': 'image/png', '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg', '.gif': 'image/gif', '.webp': 'image/webp', '.avif': 'image/avif', '.ico': 'image/x-icon',
  '.woff': 'font/woff', '.woff2': 'font/woff2', '.ttf': 'font/ttf', '.otf': 'font/otf', '.mp4': 'video/mp4',
  '.webm': 'video/webm', '.mp3': 'audio/mpeg', '.wav': 'audio/wav', '.m4a': 'audio/mp4', '.pdf': 'application/pdf', '.md': 'text/markdown; charset=utf-8',
};
const ADAPTER_TAG = '<script src="/_lectern/adapter.js"></script>';
const injectAdapter = html => /<head[^>]*>/i.test(html) ? html.replace(/<head[^>]*>/i, m => m + ADAPTER_TAG) : ADAPTER_TAG + html;

function send(res, code, body, type = 'text/plain; charset=utf-8') {
  res.writeHead(code, { 'Content-Type': type, 'Cache-Control': 'no-store' });
  res.end(body);
}
const json = (res, obj, code = 200) => send(res, code, JSON.stringify(obj), 'application/json');
function sendFile(res, file, inject) {
  fs.readFile(file, (err, data) => {
    if (err) return send(res, 404, 'Not found');
    const type = TYPES[path.extname(file).toLowerCase()] || 'application/octet-stream';
    send(res, 200, inject && type.startsWith('text/html') ? injectAdapter(data.toString('utf8')) : data, type);
  });
}
function readBody(req, limit) {
  return new Promise((resolve, reject) => {
    const chunks = []; let size = 0;
    req.on('data', c => { size += c.length; if (size > limit) { reject(new Error('Too large')); req.destroy(); } else chunks.push(c); });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}
// Join a relative path onto a folder, refusing anything that escapes it.
function inside(dir, rel) {
  const file = path.normalize(path.join(dir, rel));
  return file === dir || file.startsWith(dir + path.sep) ? file : null;
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url, 'http://localhost');
    const parts = url.pathname.split('/').slice(1).map(decodeURIComponent);
    const [first, name] = parts;

    if (url.pathname === '/') {
      if (direct.size) { res.writeHead(302, { Location: '/present/' + encodeURIComponent(listDecks()[0]) }); return res.end(); }
      return sendFile(res, path.join(APP_DIR, 'home.html'));
    }
    if (first === 'present' && deckDir(name)) return sendFile(res, path.join(APP_DIR, 'presenter.html'));
    if (first === 'audience' && deckDir(name)) return sendFile(res, path.join(APP_DIR, 'audience.html'));
    if (url.pathname === '/_lectern/adapter.js') return sendFile(res, path.join(APP_DIR, 'adapter.js'));

    if (first === 'api') {
      const [, what, deck] = parts;
      if (what === 'decks') return json(res, { library: direct.size ? null : LIBRARY, decks: listDecks().map(n => ({ name: n, ok: !!deckEntry(n) })) });
      if (what === 'upload' && req.method === 'PUT' && !direct.size) {
        // PUT /api/upload/<deck>/<relative path> with the file as the body
        if (!safeName(deck)) return send(res, 400, 'Bad deck name');
        const rel = parts.slice(3).join('/');
        const dir = path.join(LIBRARY, deck), file = inside(dir, rel);
        if (!file || !rel || parts.slice(3).some(p => p.startsWith('.'))) return send(res, 400, 'Bad path');
        const body = await readBody(req, 500e6);
        fs.mkdirSync(path.dirname(file), { recursive: true });
        fs.writeFileSync(file, body);
        return json(res, { ok: true });
      }
      if (!deckDir(deck)) return send(res, 404, 'No such deck');
      if (what === 'notes' && req.method === 'GET') return json(res, readNotes(deck));
      // Changes when an agent (or anyone) edits the deck or its notes, so open windows can refresh.
      if (what === 'version') return json(res, deckVersion(deck));
      if (what === 'order' && req.method === 'PUT') {
        // { order: [old slide index, ...] } puts the slides in a new order. Content does not change.
        const { order } = JSON.parse(await readBody(req, 1e6));
        try { reorderDeck(deck, order); } catch (e) { return send(res, 409, e.message); }
        return json(res, { ok: true });
      }
      if (what === 'notes' && req.method === 'PUT') {
        // { slide, text } saves one note. { outline: [labels], title } makes sure every slide has a heading.
        const body = JSON.parse(await readBody(req, 2e6));
        const { notes, labels } = readNotes(deck);
        if (Array.isArray(body.outline)) {
          body.outline.forEach((label, i) => { labels[i + 1] = label; });
          const fresh = !fs.existsSync(notesPath(deck));
          writeNotes(deck, notes, labels, body.outline.length, body.title);
          return json(res, { ok: true, created: fresh });
        }
        notes[body.slide] = String(body.text || '').trim();
        writeNotes(deck, notes, labels, 0, readTitle(deck));
        return json(res, { ok: true });
      }
    }

    if (first === 'deck' && deckDir(name)) {
      const dir = deckDir(name), rel = parts.slice(2).join('/');
      if (!rel) {
        const entry = deckEntry(name);
        if (!entry) return send(res, 404, 'This deck has no .html file and no images.');
        if (entry.images) return send(res, 200, injectAdapter(imageDeckHtml(name, entry.images)), TYPES['.html']);
        return sendFile(res, path.join(dir, entry.html), true);
      }
      const file = inside(dir, rel);
      if (!file) return send(res, 403, 'Forbidden');
      return sendFile(res, file, true);
    }
    send(res, 404, 'Not found');
  } catch (e) {
    send(res, 500, String(e.message));
  }
});
// ---------- reordering slides ----------
// Finds each top-level <section> block in the deck HTML (with the comments just before it),
// and writes the blocks back in the new order. If anything between slides is not just
// spaces or comments, it stops, so it never breaks a deck it does not understand.
function slideBlocks(html) {
  const re = /<\/?section\b[^>]*>/gi;
  const blocks = [];
  let depth = 0, start = -1, m;
  while ((m = re.exec(html))) {
    if (m[0][1] !== '/') { if (depth++ === 0) start = m.index; }
    else if (--depth === 0) blocks.push([start, m.index + m[0].length]);
    if (depth < 0) throw new Error('The deck HTML has an extra </section>.');
  }
  if (depth !== 0) throw new Error('The deck HTML has a <section> that is not closed.');
  return blocks;
}
function reorderDeck(deck, order) {
  const entry = deckEntry(deck), dir = deckDir(deck);
  if (!entry) throw new Error('No slides found.');
  const count = entry.images ? entry.images.length : null;
  const n = order.length;
  if (!order.every(Number.isInteger) || new Set(order).size !== n || order.some(i => i < 0 || i >= n)) throw new Error('The new order must use each slide once.');
  if (entry.images) {
    if (n !== count) throw new Error(`The deck has ${count} slides, not ${n}.`);
    fs.writeFileSync(path.join(dir, 'slides.txt'), order.map(i => entry.images[i]).join('\n') + '\n');
  } else {
    const file = path.join(dir, entry.html), html = fs.readFileSync(file, 'utf8');
    const blocks = slideBlocks(html);
    if (blocks.length !== n) throw new Error(`Lectern found ${blocks.length} slide blocks in the HTML but the deck shows ${n} slides, so it did not change anything.`);
    // Each piece = the spaces and comments before a slide + the slide itself.
    const pieces = blocks.map(([a, b], i) => {
      let from = i ? blocks[i - 1][1] : a;
      if (!i) { const lead = html.slice(0, a).match(/(?:\s*<!--(?:(?!-->)[\s\S])*-->)*\s*$/); from = a - lead[0].length; }
      const between = html.slice(from, a);
      if (between.replace(/<!--[\s\S]*?-->/g, '').trim()) throw new Error('There is other content between slides, so Lectern did not change anything.');
      return html.slice(from, b);
    });
    const head = html.slice(0, blocks[0][0] - (pieces[0].length - (blocks[0][1] - blocks[0][0])));
    const tail = html.slice(blocks[n - 1][1]);
    // Keep a copy of the old file, just in case.
    const backup = path.join(dir, '.lectern-backup');
    fs.mkdirSync(backup, { recursive: true });
    fs.writeFileSync(path.join(backup, `${Date.now()}-${entry.html}`), html);
    fs.writeFileSync(file, head + order.map(i => pieces[i]).join('') + tail);
  }
  // Notes follow their slides.
  if (fs.existsSync(notesPath(deck))) {
    const { notes, labels } = readNotes(deck), nn = {}, nl = {};
    order.forEach((old, i) => { if (notes[old + 1]) nn[i + 1] = notes[old + 1]; if (labels[old + 1]) nl[i + 1] = labels[old + 1]; });
    writeNotes(deck, nn, nl, n, readTitle(deck));
  }
}
function deckVersion(deck) {
  const dir = deckDir(deck), own = notesPath(deck);
  let slides = 0, notes = 0;
  const walk = (d, depth) => {
    for (const e of fs.readdirSync(d, { withFileTypes: true })) {
      if (e.name.startsWith('.') || e.name === 'node_modules') continue;
      const f = path.join(d, e.name);
      if (e.isDirectory()) { if (depth < 2) walk(f, depth + 1); continue; }
      const t = fs.statSync(f).mtimeMs;
      if (f === own) notes = Math.max(notes, t);
      else if (e.name === 'notes.md' || e.name.endsWith('.notes.md')) continue; // another deck's notes
      else slides = Math.max(slides, t);
    }
  };
  walk(dir, 0);
  return { slides, notes };
}
function readTitle(deck) {
  try { return (fs.readFileSync(notesPath(deck), 'utf8').match(/^# Speaker notes: (.+)$/m) || [])[1] || ''; } catch { return ''; }
}

server.on('error', err => {
  if (err.code === 'EADDRINUSE' && port < 4400) { port++; server.listen(port, '127.0.0.1'); }
  else { console.error(err.message); process.exit(1); }
});
server.on('listening', () => {
  const url = `http://localhost:${port}/`;
  console.log(direct.size ? `Lectern is presenting ${[...direct.values()][0].dir}` : `Lectern library: ${LIBRARY}`);
  console.log(`Open: ${url}`);
  console.log('Press Ctrl+C to stop.');
  if (!noOpen) {
    const cmd = process.platform === 'darwin' ? 'open' : process.platform === 'win32' ? 'cmd' : 'xdg-open';
    spawn(cmd, process.platform === 'win32' ? ['/c', 'start', '', url] : [url], { stdio: 'ignore', detached: true }).unref();
  }
});
server.listen(port, '127.0.0.1');
