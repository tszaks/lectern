// Browser test for "hold to end" and toasts. Run it in WebKit (what Safari and the Mac app use).
// Playwright is NOT a dependency of this repo. Install it somewhere else and point at it:
//   (cd /tmp/pw && npm i playwright && npx playwright install webkit)
//   PLAYWRIGHT_DIR=/tmp/pw node test/hold-to-end.test.mjs
import { createRequire } from 'node:module';
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const pwDir = process.env.PLAYWRIGHT_DIR;
if (!pwDir) { console.error('Set PLAYWRIGHT_DIR to a folder with playwright installed.'); process.exit(2); }
const { webkit } = createRequire(path.join(pwDir, 'x.js'))('playwright');

const home = fs.mkdtempSync(path.join(os.tmpdir(), 'lectern-test-'));
fs.cpSync(path.join(root, 'examples/demo'), path.join(home, 'demo'), { recursive: true });
const port = 4300 + Math.floor(Math.random() * 500);
const server = spawn('node', [path.join(root, 'bin/lectern.js'), '--no-open', '--port', String(port)], { env: { ...process.env, LECTERN_HOME: home }, stdio: 'ignore' });
const base = `http://localhost:${port}`;
for (let i = 0; i < 50; i++) { try { await fetch(base); break; } catch { await new Promise(r => setTimeout(r, 100)); } }

const results = [];
const check = (name, ok) => { results.push(ok); console.log((ok ? 'PASS ' : 'FAIL ') + name); };
const browser = await webkit.launch();
const SHOT = process.env.SHOT_DIR;

async function openShow() {
  const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
  const page = await ctx.newPage();
  const dialogs = [];
  page.on('dialog', d => { dialogs.push(d.message()); d.dismiss(); });
  await page.goto(`${base}/present/demo`);
  await page.waitForFunction(() => count > 0);
  await page.click('#open');
  await page.click('#startmenu [data-mode="presenter"]');
  await page.waitForFunction(() => document.body.classList.contains('presenting'));
  return { ctx, page, dialogs };
}
const presenting = page => page.evaluate(() => document.body.classList.contains('presenting'));

try {
  // ---- End button ----
  {
    const { ctx, page } = await openShow();
    const box = await page.locator('#endbtn').boundingBox();
    const cx = box.x + box.width / 2, cy = box.y + box.height / 2;

    await page.mouse.move(cx, cy); await page.mouse.down(); await page.waitForTimeout(80); await page.mouse.up();
    await page.waitForTimeout(1000);
    check('short click does not end the show', await presenting(page));
    check('short click shows a hint toast', await page.locator('.toast').count() > 0);

    await page.mouse.move(cx, cy); await page.mouse.down(); await page.waitForTimeout(400);
    if (SHOT) await page.screenshot({ path: path.join(SHOT, 'hold-mid.png'), clip: { x: box.x - 220, y: Math.max(0, box.y - 20), width: box.width + 240, height: box.height + 120 } });
    // Performance: while holding, only transform and opacity are animated.
    const props = await page.evaluate(() => [document.querySelector('#endbtn .fill'), document.querySelector('#endring'), document.querySelector('.toast')].filter(Boolean).map(e => getComputedStyle(e).transitionProperty));
    check('hold animation uses only transform and opacity', props.length >= 2 && props.every(p => /^(transform|opacity)$/.test(p)));
    await page.mouse.up(); await page.waitForTimeout(1200);
    check('releasing early cancels (still presenting after 1.2 s)', await presenting(page));

    await page.mouse.move(cx, cy); await page.mouse.down(); await page.waitForTimeout(1300); await page.mouse.up();
    check('full hold ends the show', !(await presenting(page)));
    await ctx.close();
  }
  {
    const { ctx, page } = await openShow();
    await page.focus('#endbtn');
    await page.keyboard.down('Enter'); await page.waitForTimeout(300); await page.keyboard.up('Enter'); await page.waitForTimeout(900);
    check('keyboard: early Enter release cancels', await presenting(page));
    await page.focus('#endbtn');
    await page.keyboard.down(' '); await page.waitForTimeout(1300); await page.keyboard.up(' ');
    check('keyboard: holding Space ends the show', !(await presenting(page)));
    await ctx.close();
  }
  {
    // Toasts must never cover what the presenter reads or uses during a talk.
    const { ctx, page } = await openShow();
    await page.evaluate(() => { showToast('Hold End to end the show'); showToast('A longer message so the stack is wide: could not save the order of the slides'); showToast('Third toast in the stack'); });
    await page.waitForTimeout(350);
    const hit = async sel => page.evaluate(sel => {
      const a = document.querySelector(sel).getBoundingClientRect();
      return [...document.querySelectorAll('.toast')].some(t => { const b = t.getBoundingClientRect(); return b.left < a.right && b.right > a.left && b.top < a.bottom && b.bottom > a.top; });
    }, sel);
    for (const sel of ['#notes', '#current', '#preview', '#timer', '#next', '#prev', '#endbtn']) check(`presenter view: toasts do not cover ${sel}`, !(await hit(sel)));
    if (SHOT) await page.screenshot({ path: path.join(SHOT, 'toast-stack.png') });
    await ctx.close();
  }
  for (const key of ['Enter', ' ']) {
    // Note: startHold has two guards (the !e.repeat test and `if (holdTimer) return`), so removing only one still passes; removing both fails here.
    // Auto-repeat: the OS sends keydown again and again while a key is held. Playwright marks the repeats repeat=true.
    const { ctx, page } = await openShow();
    await page.evaluate(() => { window.__ends = 0; const real = endPresenting; window.endPresenting = () => { window.__ends++; return real(); }; });
    await page.focus('#endbtn');
    const t0 = Date.now();
    await page.keyboard.down(key);
    let repeats = 0;
    while (Date.now() - t0 < 600) { await page.waitForTimeout(100); await page.keyboard.down(key); repeats++; }
    check(`auto-repeat ${JSON.stringify(key)}: ${repeats} repeats do not end the show early (at 600 ms)`, await presenting(page) && await page.evaluate(() => window.__ends) === 0);
    while (Date.now() - t0 < 1100) { await page.waitForTimeout(100); await page.keyboard.down(key); }
    await page.waitForTimeout(300);
    check(`auto-repeat ${JSON.stringify(key)}: the show ends once after the hold`, !(await presenting(page)) && await page.evaluate(() => window.__ends) === 1);
    await page.keyboard.up(key);
    await ctx.close();
  }
  {
    // Esc keeps its two-press rule.
    const { ctx, page } = await openShow();
    await page.keyboard.press('Escape');
    check('Esc once does not end, shows toast', (await presenting(page)) && await page.locator('.toast').count() === 1);
    await page.keyboard.press('Escape');
    check('Esc twice ends the show', !(await presenting(page)));
    await ctx.close();
  }
  {
    // Clicker keys advance slides and never end the show, even with End focused.
    const { ctx, page } = await openShow();
    for (const focusEnd of [false, true]) {
      if (focusEnd) await page.focus('#endbtn');
      for (const key of ['ArrowRight', 'PageDown', ' ', 'Enter', 'ArrowLeft', 'PageUp']) {
        // Start from slide 1 for forward keys and slide 2 for back keys, so no key is stopped by an end of the deck.
        const back = key === 'ArrowLeft' || key === 'PageUp';
        await page.evaluate(i => goTo(i), back ? 1 : 0); await page.waitForTimeout(250);
        if (focusEnd) await page.focus('#endbtn');
        const before = await page.evaluate(() => `${index}.${steps}`);
        await page.keyboard.press(key);
        await page.waitForTimeout(250);
        const after = await page.evaluate(() => `${index}.${steps}`);
        // Enter never moved slides before this change either (the deck page ignores it), so it is only checked for not ending.
        if (key !== 'Enter') check(`clicker key ${JSON.stringify(key)}${focusEnd ? ' (End focused)' : ''} moves the slide`, before !== after);
        check(`  and the show is still on`, await presenting(page));
      }
    }
    await ctx.close();
  }
  // ---- alert() replaced by toasts ----
  {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
    const page = await ctx.newPage();
    const dialogs = []; page.on('dialog', d => { dialogs.push(d.message()); d.dismiss(); });
    await page.route('**/api/new/**', r => r.fulfill({ status: 409, body: 'A project with that name already exists.' }));
    await page.goto(base + '/');
    await page.click('#new'); await page.waitForTimeout(400);
    check('home: new-project error is a toast, not alert()', dialogs.length === 0 && /already exists/.test(await page.locator('.toast').first().innerText()));
    await page.waitForTimeout(300);
    if (SHOT) await page.screenshot({ path: path.join(SHOT, 'toast-home.png') });
    await page.route('**/api/upload/**', r => r.fulfill({ status: 500, body: 'Disk is full.' }));
    await page.evaluate(() => importAsProject('x', [{ file: new Blob(['a']), path: 'index.html' }]));
    await page.waitForTimeout(300);
    check('home: import error is a toast, not alert()', dialogs.length === 0 && (await page.locator('.toast').allInnerTexts()).some(t => /Could not import index.html: Disk is full/.test(t)));
    await ctx.close();
  }
  {
    const ctx = await browser.newContext({ viewport: { width: 1280, height: 800 } });
    const page = await ctx.newPage();
    const dialogs = []; page.on('dialog', d => { dialogs.push(d.message()); d.dismiss(); });
    await page.route('**/api/order/**', r => r.fulfill({ status: 500, body: 'Could not save the order.' }));
    await page.route('**/api/upload/**', r => r.fulfill({ status: 500, body: 'Disk is full.' }));
    await page.goto(`${base}/present/demo`);
    await page.waitForFunction(() => count > 0);
    await page.evaluate(() => { pendingOrder = [1, 0, 2]; $('ordersave').click(); });
    await page.waitForTimeout(300);
    check('presenter: order-save error is a toast, not alert()', dialogs.length === 0 && (await page.locator('.toast').allInnerTexts()).some(t => /Could not save the order/.test(t)));
    await page.evaluate(() => importIntoProject([{ file: new Blob(['a']), path: 'index.html' }]));
    await page.waitForTimeout(300);
    check('presenter: import error is a toast, not alert()', dialogs.length === 0 && (await page.locator('.toast').allInnerTexts()).some(t => /Could not import index.html/.test(t)));
    // stack max 3, aria-live, hover pause
    await page.evaluate(() => { for (let i = 0; i < 5; i++) showToast('t' + i, 600); });
    check('toast stack is capped at 3', await page.locator('.toast').count() === 3);
    check('toast container is aria-live polite', await page.locator('#toasts').getAttribute('aria-live') === 'polite');
    await page.waitForTimeout(350);
    check('project view: toasts do not cover the notes', await page.evaluate(() => { const a = $('notes').getBoundingClientRect(); return ![...document.querySelectorAll('.toast')].some(t => { const b = t.getBoundingClientRect(); return b.left < a.right && b.right > a.left && b.top < a.bottom && b.bottom > a.top; }); }));
    await page.locator('.toast').last().hover();
    await page.waitForTimeout(1200);
    check('toast stays while the mouse is on it', await page.locator('.toast', { hasText: 't4' }).count() === 1);
    await page.mouse.move(5, 5);
    await page.waitForTimeout(2200);
    check('toast goes away after the mouse leaves', await page.locator('.toast').count() === 0);
    await ctx.close();
  }
} finally {
  await browser.close();
  server.kill();
  fs.rmSync(home, { recursive: true, force: true });
}
const failed = results.filter(r => !r).length;
console.log(`\n${results.length - failed}/${results.length} passed`);
process.exit(failed ? 1 : 0);
