#!/usr/bin/env node
// Lectern MCP server (stdio). Lets an AI agent make HTML slide decks and test them live in Lectern.
// It starts the normal Lectern server (bin/lectern.js) for a library folder and drives a headless
// Chrome to read slide titles and notes, take screenshots, and run checks.
import fs from 'node:fs';
import os from 'node:os';
import net from 'node:net';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { z } from 'zod';
import { chromium } from 'playwright-core';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const LECTERN_BIN = path.join(HERE, '..', 'bin', 'lectern.js');
const DEFAULT_LIBRARY = process.env.LECTERN_HOME || path.join(os.homedir(), 'Lectern');
const FRAME = { width: 1920, height: 1080 };

// ---------- small helpers ----------
class ToolError extends Error {}
const fail = msg => { throw new ToolError(msg); };
const text = s => ({ content: [{ type: 'text', text: typeof s === 'string' ? s : JSON.stringify(s, null, 2) }] });
const sleep = ms => new Promise(r => setTimeout(r, ms));
const safeName = n => typeof n === 'string' && /^[^/\\]+$/.test(n) && !n.startsWith('.');
const pad = (n, w) => String(n).padStart(w, '0');

// ---------- the Lectern server ----------
let currentLibrary = path.resolve(DEFAULT_LIBRARY);
const servers = new Map(); // library -> { port, child }

function freePort() {
  return new Promise((resolve, reject) => {
    const s = net.createServer();
    s.on('error', reject);
    s.listen(0, '127.0.0.1', () => { const { port } = s.address(); s.close(() => resolve(port)); });
  });
}
async function getJson(url, ms = 1500) {
  const r = await fetch(url, { signal: AbortSignal.timeout(ms) });
  if (!r.ok) throw new Error(`${r.status} ${await r.text()}`);
  return r.json();
}
// Look for a Lectern that already serves this library (started earlier, or by someone else).
async function findRunning(library) {
  const known = servers.get(library);
  if (known && known.child.exitCode === null) return known.port;
  for (let port = 4321; port <= 4400; port++) {
    try {
      const info = await getJson(`http://127.0.0.1:${port}/api/decks`, 300);
      if (info && info.library && path.resolve(info.library) === library) return port;
    } catch { /* nothing here */ }
  }
  return null;
}
async function startLectern(library) {
  library = path.resolve(library);
  fs.mkdirSync(library, { recursive: true });
  let port = await findRunning(library);
  let reused = true;
  if (!port) {
    reused = false;
    port = await freePort();
    const child = spawn(process.execPath, [LECTERN_BIN, '--port', String(port), '--no-open'], {
      // A small clean environment: the server needs nothing else.
      env: { PATH: process.env.PATH, HOME: os.homedir(), LECTERN_HOME: library },
      stdio: ['ignore', 'ignore', 'pipe'],
    });
    let err = '';
    child.stderr.on('data', d => { err += d; });
    servers.set(library, { port, child });
    let up = false;
    for (let i = 0; i < 50 && child.exitCode === null; i++) {
      try { await getJson(`http://127.0.0.1:${port}/api/decks`, 500); up = true; break; } catch { await sleep(100); }
    }
    if (!up) { child.kill(); servers.delete(library); fail(`Lectern did not start. ${err.trim()}`); }
  }
  currentLibrary = library;
  return { library, port, url: `http://localhost:${port}`, reused };
}
// Every deck tool calls this, so an agent does not have to call lectern_start first.
async function base() {
  const s = await startLectern(currentLibrary);
  return `http://127.0.0.1:${s.port}`;
}
async function api(method, route, body) {
  const b = await base();
  const r = await fetch(b + route, {
    method, headers: body ? { 'Content-Type': 'application/json' } : {}, body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(10000),
  });
  const raw = await r.text();
  if (!r.ok) fail(`Lectern said ${r.status} for ${method} ${route}: ${raw}`);
  try { return JSON.parse(raw); } catch { return raw; }
}
const enc = encodeURIComponent;
async function requireDeck(deck) {
  if (!safeName(deck)) fail(`Bad deck name: ${JSON.stringify(deck)}`);
  const { decks } = await api('GET', '/api/decks');
  const found = decks.find(d => d.name === deck);
  if (!found) fail(`No deck named "${deck}" in ${currentLibrary}. Decks here: ${decks.map(d => d.name).join(', ') || '(none)'}`);
  if (!found.ok) fail(`"${deck}" has no .html file and no images.`);
}

// ---------- the headless browser ----------
let browserPromise = null;
function getBrowser() {
  if (!browserPromise) {
    browserPromise = chromium.launch({ channel: 'chrome', headless: true }).catch(e => {
      browserPromise = null;
      fail('Could not start Google Chrome. Lectern checks use the Chrome that is installed on this computer ' +
        `(playwright channel "chrome"). Install Chrome, then try again. Details: ${String(e.message).split('\n')[0]}`);
    });
  }
  return browserPromise;
}
// Open a deck at 1920x1080 the way the presenter does. Collects problems while it loads.
async function openDeck(deck) {
  await requireDeck(deck);
  const browser = await getBrowser();
  const context = await browser.newContext({ viewport: FRAME, deviceScaleFactor: 1 });
  const page = await context.newPage();
  const problems = { console: [], failed: [], pageErrors: [] };
  page.on('console', m => {
    if (m.type() !== 'error') return;
    const where = m.location().url;
    if (/\/favicon\.ico$/.test(where || '')) return; // browsers ask for this on their own
    problems.console.push(where && /^Failed to load resource/.test(m.text()) ? `${m.text()} (${where})` : m.text());
  });
  page.on('pageerror', e => problems.pageErrors.push(String(e.message || e)));
  page.on('requestfailed', r => problems.failed.push(`${r.url()} (${r.failure()?.errorText || 'failed'})`));
  page.on('response', r => { if (r.status() >= 400) problems.failed.push(`${r.url()} (HTTP ${r.status()})`); });
  const b = await base();
  try {
    await page.goto(`${b}/deck/${enc(deck)}/`, { waitUntil: 'load', timeout: 20000 });
  } catch (e) {
    problems.failed.push(`${b}/deck/${deck}/ (page did not finish loading: ${String(e.message).split('\n')[0]})`);
  }
  await page.waitForTimeout(400);
  return { page, context, problems, close: () => context.close().catch(() => {}) };
}

// This code runs inside the deck page. It uses the same rules as app/adapter.js, so the
// slides, labels and notes match what Lectern shows.
function installReader() {
  const SLIDE_SELECTORS = ['.reveal .slides > section', 'section.slide', '.slide', 'body > section'];
  const slides = () => {
    for (const sel of SLIDE_SELECTORS) { const f = document.querySelectorAll(sel); if (f.length) return [...f]; }
    return [];
  };
  const isVisible = el => {
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden' || Number(cs.opacity) === 0) return false;
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0 && r.right > 0 && r.bottom > 0 && r.left < innerWidth && r.top < innerHeight;
  };
  const currentIndex = () => {
    const all = slides();
    let i = all.findIndex(s => s.matches('.active, .present, .current, [aria-current="true"], [aria-current="step"]'));
    if (i < 0) i = all.findIndex(isVisible);
    if (i < 0) { const h = parseInt(location.hash.slice(1), 10); if (h > 0) i = Math.min(h, all.length) - 1; }
    return Math.max(0, i);
  };
  const notesFor = slide => {
    if (slide.dataset.notes) return slide.dataset.notes;
    const aside = slide.querySelector('aside.notes, .notes');
    return aside ? (aside.innerText || '').trim() || aside.textContent.trim() : '';
  };
  const labelFor = slide => {
    const clean = t => (t || '').replace(/\s+/g, ' ').trim();
    const h = slide.querySelector('h1, h2, h3, [class*="title"]');
    let label = clean(h && h.textContent);
    if (!label) {
      const copy = slide.cloneNode(true);
      copy.querySelectorAll('aside.notes, .notes, script, style').forEach(n => n.remove());
      label = clean(copy.textContent);
    }
    if (!label) { const img = slide.querySelector('img'); label = img ? clean(img.alt) || decodeURIComponent(img.src.split('/').pop()) : ''; }
    return label.length > 70 ? label.slice(0, 67) + '…' : label;
  };
  const hasHiddenSteps = slide => !!slide && !!slide.querySelector('.step:not(.shown), .fragment:not(.visible)');
  window.__lecternMcp = { slides, currentIndex, notesFor, labelFor, hasHiddenSteps, isVisible };
}
async function prepare(page) {
  await page.evaluate(installReader);
  // Hide notes from the picture, the same way Lectern does for the audience.
  await page.addStyleTag({ content: 'aside.notes{display:none!important}' });
}
const readState = page => page.evaluate(() => {
  const t = window.__lecternMcp, all = t.slides();
  return { index: t.currentIndex(), count: all.length, hidden: t.hasHiddenSteps(all[t.currentIndex()]) };
});

// Walk the deck from the first slide to the last, with the keyboard, like Lectern does.
// visit({index, count, step, steps}) runs once for each slide (step 0) and, if allSteps,
// again after each click-to-reveal step.
async function walk(page, visit, { allSteps = false, settle = 350 } = {}) {
  const first = await readState(page);
  if (!first.count) return 0;
  await page.keyboard.press('Home');
  await page.waitForTimeout(settle);
  let state = await readState(page);
  const visited = new Set();
  let step = 0;
  for (let guard = 0; guard < 3000; guard++) {
    if (!visited.has(state.index)) { visited.add(state.index); step = 0; await visit({ ...state, step }); }
    const beforeIndex = state.index, hadSteps = state.hidden;
    await page.keyboard.press('ArrowRight');
    await page.waitForTimeout(settle);
    state = await readState(page);
    if (state.index === beforeIndex) {
      if (hadSteps) { step++; if (allSteps) await visit({ ...state, step }); continue; }
      if (state.index >= state.count - 1) break; // last slide
      // Some decks ignore a key while a slide change is still animating. Try again before giving up.
      let moved = false;
      for (let retry = 0; retry < 3 && !moved; retry++) {
        await page.waitForTimeout(700);
        await page.keyboard.press('ArrowRight');
        await page.waitForTimeout(settle);
        state = await readState(page);
        moved = state.index !== beforeIndex || state.hidden !== hadSteps;
      }
      if (!moved) break; // the deck stopped moving
    }
  }
  return visited.size;
}

// A 960-wide JPEG for the agent to look at. Scaled in the browser, so no extra tools are needed.
async function thumbnail(png) {
  const browser = await getBrowser();
  if (!thumbnail.page) thumbnail.page = await (await browser.newContext()).newPage();
  const b64 = png.toString('base64');
  return thumbnail.page.evaluate(async src => {
    const img = new Image();
    await new Promise((res, rej) => { img.onload = res; img.onerror = rej; img.src = 'data:image/png;base64,' + src; });
    const c = document.createElement('canvas');
    c.width = 960; c.height = Math.round(img.height * 960 / img.width);
    c.getContext('2d').drawImage(img, 0, 0, c.width, c.height);
    return c.toDataURL('image/jpeg', 0.72).split(',')[1];
  }, b64);
}

// ---------- notes ----------
async function loadNotesApi(deck) { return api('GET', `/api/notes/${enc(deck)}`); }

async function readOutline(deck) {
  const d = await openDeck(deck);
  try {
    await prepare(d.page);
    const dom = await d.page.evaluate(() => {
      const t = window.__lecternMcp;
      return { title: document.title, labels: t.slides().map(t.labelFor), notes: t.slides().map(t.notesFor) };
    });
    const file = await loadNotesApi(deck);
    const slides = dom.labels.map((label, i) => {
      const fileNote = (file.notes && file.notes[i + 1]) || '';
      // The same rule as the presenter: notes.md wins if it is not empty.
      const note = fileNote.trim() ? fileNote : dom.notes[i] || '';
      return { number: i + 1, label, notes: note, notesFrom: fileNote.trim() ? 'notes.md' : dom.notes[i] ? 'html' : 'none' };
    });
    return { deck, title: dom.title, slideCount: slides.length, slides, fileLabels: file.labels || {}, problems: d.problems };
  } finally { await d.close(); }
}

// ---------- tools ----------
const server = new McpServer({ name: 'lectern', version: '0.1.0' });
const guarded = fn => async args => {
  try { return await fn(args); } catch (e) {
    if (e instanceof ToolError) return { isError: true, content: [{ type: 'text', text: e.message }] };
    return { isError: true, content: [{ type: 'text', text: `Unexpected error: ${e && e.stack || e}` }] };
  }
};
const tool = (name, description, inputSchema, fn) => server.registerTool(name, { description, inputSchema }, guarded(fn));
const deckArg = z.string().describe('Deck folder name in the library');

tool('lectern_start',
  'Make sure a Lectern server is running for a library folder, and return its address. Reuses a server that already runs. Other tools start it for you, so call this only to pick a different library or to get the address.',
  { library: z.string().optional().describe('Library folder. Default: ~/Lectern (or $LECTERN_HOME)') },
  async ({ library }) => text(await startLectern(library ? path.resolve(library.replace(/^~(?=$|\/)/, os.homedir())) : currentLibrary)));

tool('list_decks', 'List the decks in the current library.', {},
  async () => { const r = await api('GET', '/api/decks'); return text({ library: r.library, decks: r.decks }); });

tool('create_deck',
  'Write a new deck folder into the library. An HTML deck needs an index.html (slides are <section class="slide">, one per slide, moved with the arrow keys). Add images and fonts as more files. Use encoding "base64" for binary files. Refuses to overwrite a deck unless overwrite is true.',
  {
    name: z.string().describe('Folder name for the deck, for example "q3-review". No slashes.'),
    files: z.array(z.object({
      path: z.string().describe('Path inside the deck folder, for example "index.html" or "img/logo.png"'),
      content: z.string(),
      encoding: z.enum(['utf8', 'base64']).optional(),
    })).min(1),
    overwrite: z.boolean().optional().describe('Replace the deck if it already exists'),
  },
  async ({ name, files, overwrite }) => {
    if (!safeName(name)) fail('Bad deck name. Use a plain folder name with no slashes and no leading dot.');
    const lib = (await startLectern(currentLibrary)).library;
    const dir = path.join(lib, name);
    if (fs.existsSync(dir) && !overwrite) fail(`"${name}" already exists. Use another name, or set overwrite to true.`);
    const targets = files.map(f => {
      const rel = f.path.replace(/\\/g, '/');
      const parts = rel.split('/');
      if (!rel || path.isAbsolute(rel) || parts.some(p => p === '' || p === '.' || p === '..' || p.startsWith('.')))
        fail(`Bad file path: ${JSON.stringify(f.path)}. Use a relative path inside the deck, with no "..", and no names that start with a dot.`);
      const file = path.normalize(path.join(dir, rel));
      if (!file.startsWith(dir + path.sep)) fail(`Path leaves the deck folder: ${JSON.stringify(f.path)}`);
      return { file, rel, data: f.encoding === 'base64' ? Buffer.from(f.content, 'base64') : Buffer.from(f.content, 'utf8') };
    });
    if (new Set(targets.map(t => t.file)).size !== targets.length) fail('Two files have the same path.');
    // Build in a hidden folder first, then move it in, so Lectern never shows a half-written deck.
    const stage = path.join(lib, `.mcp-stage-${process.pid}-${Date.now()}`);
    try {
      for (const t of targets) {
        const f = path.join(stage, t.rel);
        fs.mkdirSync(path.dirname(f), { recursive: true });
        fs.writeFileSync(f, t.data);
      }
      if (overwrite && fs.existsSync(dir)) {
        // Keep notes.md if the new files do not bring one (the speaker's notes are theirs).
        const oldNotes = path.join(dir, 'notes.md'), newNotes = path.join(stage, 'notes.md');
        if (fs.existsSync(oldNotes) && !fs.existsSync(newNotes)) fs.copyFileSync(oldNotes, newNotes);
        fs.rmSync(dir, { recursive: true, force: true });
      }
      fs.renameSync(stage, dir);
    } finally { fs.rmSync(stage, { recursive: true, force: true }); }
    return text({ ok: true, deck: name, folder: dir, files: targets.map(t => t.rel), present: `${(await startLectern(lib)).url}/present/${enc(name)}` });
  });

tool('get_outline',
  'Slide count, and for each slide its number, title (label) and speaker notes. Read from the real deck in a headless browser with the same rules Lectern uses. notes.md wins over notes written in the HTML when it is not empty.',
  { deck: deckArg },
  async ({ deck }) => { const o = await readOutline(deck); delete o.problems; delete o.fileLabels; return text(o); });

tool('set_notes', 'Set the speaker notes for one slide (saved in the deck\'s notes.md). Slide numbers start at 1. An empty text clears the note.',
  { deck: deckArg, slide: z.number().int().min(1), text: z.string() },
  async ({ deck, slide, text: note }) => {
    const o = await readOutline(deck);
    if (slide > o.slideCount) fail(`"${deck}" has ${o.slideCount} slides. There is no slide ${slide}.`);
    // Make sure notes.md has a heading with a title for every slide, so the file stays readable.
    if (Object.keys(o.fileLabels).length < o.slideCount)
      await api('PUT', `/api/notes/${enc(deck)}`, { outline: o.slides.map(s => s.label), title: o.title });
    const r = await api('PUT', `/api/notes/${enc(deck)}`, { slide, text: note });
    const back = await loadNotesApi(deck);
    return text({ ok: !!r.ok, deck, slide, saved: back.notes[String(slide)] ?? '' });
  });

tool('reorder_slides',
  'Put the slides in a new order. order lists the OLD slide numbers (starting at 1) in the NEW order, for example [1,3,2,4] swaps slides 2 and 3. It must list every slide once. Notes move with their slides.',
  { deck: deckArg, order: z.array(z.number().int().min(1)).min(1) },
  async ({ deck, order }) => {
    const o = await readOutline(deck);
    const sorted = [...order].sort((a, b) => a - b);
    if (order.length !== o.slideCount || sorted.some((n, i) => n !== i + 1))
      fail(`order must list each slide number from 1 to ${o.slideCount} exactly once. Got: [${order.join(', ')}]`);
    const r = await api('PUT', `/api/order/${enc(deck)}`, { order: order.map(n => n - 1) });
    const after = await readOutline(deck);
    return text({ ok: r && r.ok !== false, result: r, newOrder: after.slides.map(s => `${s.number}. ${s.label}`) });
  });

tool('screenshot_slides',
  'Take pictures of slides at 1920x1080, the size Lectern draws. Returns PNG file paths and small JPEGs you can look at. slides: slide numbers from 1 (default: all). step "start" shows each slide before any click-to-reveal step; "all" also shows the slide after each step.',
  {
    deck: deckArg,
    slides: z.array(z.number().int().min(1)).optional(),
    step: z.enum(['start', 'all']).optional(),
    maxImages: z.number().int().min(1).max(40).optional().describe('Most pictures to return inline. Default 12. All pictures are still saved to disk.'),
  },
  async ({ deck, slides: want, step = 'start', maxImages = 12 }) => {
    const d = await openDeck(deck);
    try {
      await prepare(d.page);
      const total = (await readState(d.page)).count;
      if (!total) fail('No slides found. Slides must match one of: .reveal .slides > section, section.slide, .slide, body > section.');
      const bad = (want || []).filter(n => n > total);
      if (bad.length) fail(`"${deck}" has ${total} slides. No slide ${bad.join(', ')}.`);
      const wanted = want ? new Set(want) : null;
      const outDir = fs.mkdtempSync(path.join(os.tmpdir(), `lectern-${deck.replace(/[^\w.-]/g, '_')}-`));
      const shots = [];
      await walk(d.page, async s => {
        if (wanted && !wanted.has(s.index + 1)) return;
        const file = path.join(outDir, `slide-${pad(s.index + 1, 2)}${s.step ? `-step${s.step}` : ''}.png`);
        const png = await d.page.screenshot({ type: 'png' });
        fs.writeFileSync(file, png);
        shots.push({ slide: s.index + 1, step: s.step, file, png });
      }, { allSteps: step === 'all' });
      const missing = want ? want.filter(n => !shots.some(s => s.slide === n)) : [];
      const content = [{ type: 'text', text: JSON.stringify({
        deck, slideCount: total, folder: outDir,
        files: shots.map(s => ({ slide: s.slide, ...(s.step ? { step: s.step } : {}), file: s.file })),
        ...(missing.length ? { notReached: missing } : {}),
        ...(shots.length > maxImages ? { note: `Showing the first ${maxImages} of ${shots.length} pictures. The rest are on disk.` } : {}),
      }, null, 2) }];
      for (const s of shots.slice(0, maxImages)) {
        content.push({ type: 'text', text: `Slide ${s.slide}${s.step ? `, step ${s.step}` : ''}` });
        content.push({ type: 'image', data: await thumbnail(s.png), mimeType: 'image/jpeg' });
      }
      return { content };
    } finally { await d.close(); }
  });

tool('check_deck',
  'Test a deck live: open it at 1920x1080, walk every slide with the keyboard, and report slide count, console errors, failed network requests, content outside the frame, missing images, and slides without speaker notes.',
  { deck: deckArg },
  async ({ deck }) => {
    const d = await openDeck(deck);
    try {
      await prepare(d.page);
      const dom = await d.page.evaluate(() => {
        const t = window.__lecternMcp;
        return { title: document.title, labels: t.slides().map(t.labelFor), notes: t.slides().map(t.notesFor) };
      });
      const file = await loadNotesApi(deck);
      const perSlide = [];
      const visitedCount = await walk(d.page, async s => {
        if (s.step) return;
        const found = await d.page.evaluate(({ W, H }) => {
          const t = window.__lecternMcp, slide = t.slides()[t.currentIndex()];
          const out = { overflow: [], missingImages: [], scrolls: null };
          if (!slide) return out;
          const name = el => el.tagName.toLowerCase() + (el.id ? '#' + el.id : '') +
            (typeof el.className === 'string' && el.className.trim() ? '.' + el.className.trim().split(/\s+/).slice(0, 2).join('.') : '');
          const clipped = el => { // is it cut off by a parent that hides overflow, inside the frame?
            for (let p = el.parentElement; p && p !== document.body.parentElement; p = p.parentElement) {
              const cs = getComputedStyle(p);
              if (/(hidden|clip)/.test(cs.overflowX + cs.overflowY)) {
                const r = p.getBoundingClientRect();
                if (r.left >= -2 && r.top >= -2 && r.right <= W + 2 && r.bottom <= H + 2) return true;
              }
              if (p === slide) break;
            }
            return false;
          };
          for (const el of slide.querySelectorAll('*')) {
            if (el.closest('aside.notes, .notes, script, style')) continue;
            const cs = getComputedStyle(el);
            if (cs.display === 'none' || cs.visibility === 'hidden' || Number(cs.opacity) === 0) continue;
            const r = el.getBoundingClientRect();
            if (r.width <= 0 || r.height <= 0) continue;
            const over = { right: Math.round(r.right - W), bottom: Math.round(r.bottom - H), left: Math.round(-r.left), top: Math.round(-r.top) };
            if ((over.right > 2 || over.bottom > 2 || over.left > 2 || over.top > 2) && !clipped(el)) {
              out.overflow.push({ element: name(el), sample: (el.textContent || '').replace(/\s+/g, ' ').trim().slice(0, 40), pxPastFrame: Object.fromEntries(Object.entries(over).filter(([, v]) => v > 2)) });
            }
          }
          for (const img of slide.querySelectorAll('img')) {
            if (img.loading === 'lazy') img.loading = 'eager';
            if (img.complete && img.naturalWidth === 0) out.missingImages.push(img.getAttribute('src') || '(no src)');
          }
          if (slide.clientHeight > 0 && slide.scrollHeight > H + 2 && slide.scrollHeight > slide.clientHeight + 2)
            out.scrolls = { scrollHeight: slide.scrollHeight, clientHeight: slide.clientHeight };
          return out;
        }, { W: FRAME.width, H: FRAME.height });
        perSlide[s.index] = found;
      });
      const count = dom.labels.length;
      const slides = dom.labels.map((label, i) => {
        const fileNote = (file.notes && file.notes[i + 1]) || '';
        const hasNotes = !!(fileNote.trim() || dom.notes[i]);
        const f = perSlide[i] || { overflow: [], missingImages: [], scrolls: null };
        return { number: i + 1, label, hasNotes, overflow: f.overflow.slice(0, 4), missingImages: f.missingImages, ...(f.scrolls ? { taller: f.scrolls } : {}) };
      });
      const p = d.problems;
      const issues = {
        consoleErrors: [...new Set([...p.console, ...p.pageErrors])],
        failedRequests: [...new Set(p.failed)],
        overflowingSlides: slides.filter(s => s.overflow.length || s.taller).map(s => ({ slide: s.number, label: s.label, overflow: s.overflow, ...(s.taller ? { taller: s.taller } : {}) })),
        missingImages: slides.filter(s => s.missingImages.length).map(s => ({ slide: s.number, label: s.label, images: s.missingImages })),
        slidesWithoutNotes: slides.filter(s => !s.hasNotes).map(s => s.number),
        notReached: visitedCount < count ? `Keyboard walk reached ${visitedCount} of ${count} slides. Check that ArrowRight moves the deck.` : undefined,
      };
      const problemCount = issues.consoleErrors.length + issues.failedRequests.length + issues.overflowingSlides.length + issues.missingImages.length + (issues.notReached ? 1 : 0);
      return text({
        deck, title: dom.title, slideCount: count, frame: `${FRAME.width}x${FRAME.height}`,
        verdict: problemCount ? `${problemCount} problem(s) found` : 'No problems found' + (issues.slidesWithoutNotes.length ? ` (but ${issues.slidesWithoutNotes.length} slide(s) have no notes)` : ''),
        ...issues,
      });
    } finally { await d.close(); }
  });

tool('present_url', 'Return the presenter page address for a deck. Open it in a browser to present.',
  { deck: deckArg },
  async ({ deck }) => {
    await requireDeck(deck);
    const s = await startLectern(currentLibrary);
    return text({ presenter: `${s.url}/present/${enc(deck)}`, audience: `${s.url}/audience/${enc(deck)}`, deckOnly: `${s.url}/deck/${enc(deck)}/` });
  });

// ---------- start and stop ----------
let closing = false;
async function shutdown() {
  if (closing) return; closing = true;
  for (const { child } of servers.values()) { try { child.kill(); } catch { /* already gone */ } }
  try { const b = browserPromise && await browserPromise; if (b) await b.close(); } catch { /* already gone */ }
}
process.on('exit', () => { for (const { child } of servers.values()) { try { child.kill(); } catch { /* gone */ } } });
for (const sig of ['SIGINT', 'SIGTERM', 'SIGHUP']) process.on(sig, async () => { await shutdown(); process.exit(0); });
process.stdin.on('end', async () => { await shutdown(); process.exit(0); });

await server.connect(new StdioServerTransport());
