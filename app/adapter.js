// Lectern adapter. Lectern injects this into the deck. It runs inside each copy of the deck
// (audience, presenter "now", presenter "next") and:
//  - finds the slides, the current slide, and each slide's notes
//  - sends navigation keys (keyboard or USB clicker) up to Lectern instead of acting alone,
//    so every copy of the deck gets the same key at the same time
//  - mirrors clicks on interactive parts between the audience and the presenter
// When the deck is opened directly (not inside Lectern) it does nothing.
(() => {
  const frame = window.frameElement;
  if (!frame || !frame.dataset.role || window.__lectern) return;
  window.__lectern = true;
  const role = frame.dataset.role; // 'audience' | 'current' | 'preview'
  const post = msg => window.parent.postMessage({ lectern: true, role, ...msg }, location.origin);

  // Keys that move the deck. USB clickers send PageDown/PageUp (some send arrows).
  const NAV_KEYS = new Set(['ArrowRight', 'ArrowLeft', 'ArrowUp', 'ArrowDown', 'PageDown', 'PageUp', ' ', 'Enter', 'Backspace', 'Home', 'End']);
  // Keys Lectern itself uses: blank screen (clicker "blank" buttons send B or period).
  const LECTERN_KEYS = new Set(['b', 'B', '.']);
  const KEY_CODES = { ArrowLeft: 37, ArrowUp: 38, ArrowRight: 39, ArrowDown: 40, PageUp: 33, PageDown: 34, ' ': 32, Enter: 13, Backspace: 8, Home: 36, End: 35 };
  const KEY_NAMES = { ' ': 'Space', Enter: 'Enter', Backspace: 'Backspace' };

  const style = document.createElement('style');
  style.textContent = 'aside.notes{display:none!important}' +
    (role === 'preview'
      // Freeze the "Next" copy: no fades and no moving parts, so it costs little on a slow Mac.
      ? '*,*::before,*::after{transition-duration:0s!important;transition-delay:0s!important;' +
        'animation-delay:0s!important;animation-duration:1ms!important;animation-iteration-count:1!important;animation-fill-mode:both!important}'
      : '');
  document.documentElement.appendChild(style);

  // ---------- reading the deck ----------
  const SLIDE_SELECTORS = ['.reveal .slides > section', 'section.slide', '.slide', 'body > section'];
  function slides() {
    for (const sel of SLIDE_SELECTORS) {
      const found = document.querySelectorAll(sel);
      if (found.length) return [...found];
    }
    return [];
  }
  function isVisible(el) {
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden' || Number(cs.opacity) === 0) return false;
    const r = el.getBoundingClientRect();
    return r.width > 0 && r.height > 0 && r.right > 0 && r.bottom > 0 && r.left < innerWidth && r.top < innerHeight;
  }
  function currentIndex() {
    const all = slides();
    let i = all.findIndex(s => s.matches('.active, .present, .current, [aria-current="true"], [aria-current="step"]'));
    if (i < 0) i = all.findIndex(isVisible);
    if (i < 0) { const h = parseInt(location.hash.slice(1), 10); if (h > 0) i = Math.min(h, all.length) - 1; }
    return Math.max(0, i);
  }
  function notesFor(slide) {
    if (slide.dataset.notes) return slide.dataset.notes;
    const aside = slide.querySelector('aside.notes, .notes');
    return aside ? aside.innerText.trim() || aside.textContent.trim() : '';
  }
  // A short label for each slide, so people and agents can tell which notes go where.
  function labelFor(slide) {
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
  }
  // For slides that are just one picture (image decks), the picture's address, for the "Next" card.
  function imageOf(slide) {
    const only = slide.children.length === 1 && slide.firstElementChild;
    return only && only.tagName === 'IMG' ? only.src : '';
  }
  function hasHiddenSteps(slide) {
    return !!slide.querySelector('.step:not(.shown), .fragment:not(.visible)');
  }
  // Count what a slide has revealed so far. Decks mark revealed parts with "shown" (or reveal.js "visible").
  const shownSteps = slide => slide ? slide.querySelectorAll('.shown, .fragment.visible').length : 0;
  const hideSteps = root => root.querySelectorAll('.shown, .fragment.visible').forEach(el => el.classList.remove('shown', 'visible'));
  // Press a key and report whether the deck changed anything. Lectern does not need to know
  // the deck's own names for steps: a press that changes nothing means the deck is at its end.
  const watcher = new MutationObserver(() => {});
  function pressAndSee(key) {
    watcher.observe(document.body, { subtree: true, childList: true, attributes: true, characterData: true });
    press(key);
    const changed = watcher.takeRecords().length > 0;
    watcher.disconnect();
    return changed;
  }

  let lastSent = '';
  // Titles and notes are read once, and again only when slides are added or removed.
  // Every slide change after that sends just the slide number, which keeps things fast.
  let outlineDirty = true;
  function report(force) {
    if (role === 'strip') return;
    const all = slides();
    const index = currentIndex();
    const state = { type: 'state', index, count: all.length, title: document.title, steps: shownSteps(all[index]) };
    const key = JSON.stringify(state);
    if (outlineDirty || force) {
      outlineDirty = false;
      Object.assign(state, { notes: all.map(notesFor), labels: all.map(labelFor), images: all.map(imageOf) });
      force = true;
    }
    if (force || key !== lastSent) { lastSent = key; post(state); }
  }
  let pending = null;
  // Report on the next screen refresh. Many changes at once still make one report.
  const reportSoon = () => { if (!pending) pending = setTimeout(() => { pending = null; report(); }, 0); };

  // ---------- doing things to the deck ----------
  function press(key) {
    const target = document.activeElement && document.activeElement !== document.documentElement ? document.activeElement : document.body;
    const ev = new KeyboardEvent('keydown', { key, code: KEY_NAMES[key] || key, bubbles: true, cancelable: true });
    // Older decks (reveal.js and others) read keyCode, which the constructor cannot set.
    Object.defineProperty(ev, 'keyCode', { get: () => KEY_CODES[key] || 0 });
    Object.defineProperty(ev, 'which', { get: () => KEY_CODES[key] || 0 });
    target.dispatchEvent(ev);
    target.dispatchEvent(new KeyboardEvent('keyup', { key, code: KEY_NAMES[key] || key, bubbles: true }));
  }
  // Jump to slide n with the first `steps` click-to-reveal steps shown.
  function goTo(n, steps = 0) {
    if (window.Reveal && typeof window.Reveal.slide === 'function') { window.Reveal.slide(n, 0, steps - 1); return reportSoon(); }
    // Going forward: step from where we are (the "Next" view usually moves just one slide).
    // Going back: start again from the first slide, with all steps hidden.
    if (n < currentIndex()) {
      slides().forEach(hideSteps);
      press('Home');
    }
    for (let i = 0; i < 2000 && currentIndex() < n; i++) {
      const before = currentIndex();
      if (!pressAndSee('ArrowRight') && currentIndex() === before) break; // the deck did nothing: it is at its end
    }
    // The slide we arrived at starts with nothing revealed, then reveals as many parts as asked.
    const target = slides()[n];
    if (target) hideSteps(target);
    for (let i = 0; i < steps && currentIndex() === n; i++) {
      if (!pressAndSee('ArrowRight')) break;
      if (currentIndex() !== n) { press('ArrowLeft'); break; } // went one too far
    }
    reportSoon();
  }
  function pathTo(el) {
    const path = [];
    while (el && el !== document.body && el.parentElement) {
      path.unshift([...el.parentElement.children].indexOf(el));
      el = el.parentElement;
    }
    return path;
  }
  function fromPath(path) {
    let el = document.body;
    for (const i of path) { el = el && el.children[i]; }
    return el;
  }

  // ---------- events ----------
  addEventListener('keydown', e => {
    if (role === 'strip') return;
    if (!e.isTrusted) return reportSoon(); // our own replayed key: let the deck act on it
    const t = e.target;
    if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return;
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.key === 'Escape' && role === 'audience' && window.parent.parent !== window.parent) {
      window.parent.parent.postMessage({ lecternExit: true }, location.origin); // leave full screen
      return;
    }
    if (e.key === 'f' || e.key === 'F') {
      // Full screen the whole Lectern window (not only this frame), so the deck keeps its 1920x1080 size.
      e.preventDefault(); e.stopImmediatePropagation();
      const doc = window.parent.document;
      doc.fullscreenElement ? doc.exitFullscreen() : doc.documentElement.requestFullscreen().catch(() => {});
      return;
    }
    if (NAV_KEYS.has(e.key) || LECTERN_KEYS.has(e.key)) {
      e.preventDefault();
      e.stopImmediatePropagation();
      post({ type: 'key', key: e.key });
    }
  }, true);

  addEventListener('click', e => {
    if (!e.isTrusted || role === 'preview' || role === 'strip') return;
    post({ type: 'click', path: pathTo(e.target) });
    reportSoon();
  }, true);

  addEventListener('message', e => {
    if (e.source !== window.parent || !e.data || !e.data.lectern) return;
    const m = e.data;
    if (m.type === 'key') press(m.key);
    else if (m.type === 'click') { const el = fromPath(m.path); if (el) el.click(); }
    else if (m.type === 'goto') goTo(m.index, m.steps);
    else if (m.type === 'report') report(true);
    else if (m.type === 'media') applyMedia(m);
    else if (m.type === 'here') stripHere(m.index);
    reportSoon();
  });
  addEventListener('hashchange', reportSoon);

  // ---------- video ----------
  // Videos play in every view at the same time: with sound on the audience screen, muted for the presenter.
  // Play, pause and jumps in one view happen in the others. This works for <video> and for YouTube
  // players. Other embedded players (for example TED's) cannot be controlled, so they play on the
  // audience screen only.
  const isYouTube = f => /youtube(-nocookie)?\.com\/embed\//.test(f.src || f.dataset.src || '');
  const players = new Map(); // YouTube iframe -> { state, time, quietUntil }
  const yt = (f, func, args = []) => f.contentWindow && f.contentWindow.postMessage(JSON.stringify({ event: 'command', func, args }), '*');
  const shareMedia = (el, state, time) => post({ type: 'media', path: pathTo(el), state, time });

  function quiet(root) {
    root.querySelectorAll('iframe').forEach(f => {
      if (isYouTube(f)) {
        // YouTube only reports and takes commands when "enablejsapi=1" is in its address.
        for (const attr of ['src', 'data-src']) {
          const v = f.getAttribute(attr);
          if (v && !/enablejsapi=1/.test(v)) f.setAttribute(attr, v + (v.includes('?') ? '&' : '?') + 'enablejsapi=1');
        }
        if (role !== 'preview' && role !== 'strip' && !f.dataset.lecternWatched) {
          f.dataset.lecternWatched = '1';
          f.addEventListener('load', () => {
            const p = { state: -1, time: 0, quietUntil: 0, heard: false };
            players.set(f, p);
            // The player may not be ready yet, so say "listening" until it answers (as YouTube's own script does).
            let tries = 0;
            const hello = setInterval(() => {
              if (p.heard || ++tries > 40 || !f.contentWindow) return clearInterval(hello);
              f.contentWindow.postMessage(JSON.stringify({ event: 'listening', id: 1, channel: 'widget' }), '*');
            }, 250);
          });
        }
        if (role !== 'preview' && role !== 'strip') return;
      }
      if (role !== 'audience' && !f.srcdoc) {
        f.srcdoc = '<body style="margin:0;display:grid;place-items:center;height:100vh;background:#111;color:#999;font:600 28px system-ui">Plays on the audience screen</body>';
      }
    });
    if (role !== 'audience') root.querySelectorAll('video, audio').forEach(m => { m.muted = true; });
  }

  // Messages from YouTube players: "ready", and the play state with the time.
  addEventListener('message', e => {
    if (!/youtube(-nocookie)?\.com$/.test(new URL(e.origin || 'null', location.href).hostname || '')) return;
    let d; try { d = typeof e.data === 'string' ? JSON.parse(e.data) : e.data; } catch { return; }
    const f = [...players.keys()].find(x => x.contentWindow === e.source);
    if (!f || !d) return;
    const p = players.get(f);
    if (!p.heard) { p.heard = true; if (role !== 'audience') yt(f, 'mute'); }
    const info = d.info || {};
    if (typeof info.currentTime === 'number') p.time = info.currentTime;
    if (typeof info.playerState === 'number' && info.playerState !== p.state) {
      p.state = info.playerState;
      // 1 = playing, 2 = paused. Share only changes the person made, not ones Lectern made.
      if ((p.state === 1 || p.state === 2) && Date.now() > p.quietUntil) shareMedia(f, p.state === 1 ? 'play' : 'pause', p.time);
    }
  });

  // <video> and <audio>
  const mediaQuietUntil = new WeakMap();
  for (const type of ['play', 'pause', 'seeked']) {
    document.addEventListener(type, e => {
      const el = e.target;
      if (role === 'preview' || (mediaQuietUntil.get(el) || 0) > Date.now()) return;
      shareMedia(el, el.paused ? 'pause' : 'play', el.currentTime);
    }, true);
  }

  function applyMedia(m) {
    const el = fromPath(m.path);
    if (!el || role === 'preview') return;
    if (el.tagName === 'IFRAME') {
      const p = players.get(el);
      if (!p) return;
      p.quietUntil = Date.now() + 2000;
      if (role !== 'audience') yt(el, 'mute');
      if (Math.abs(p.time - m.time) > 2) yt(el, 'seekTo', [m.time, true]);
      yt(el, m.state === 'play' ? 'playVideo' : 'pauseVideo');
    } else if (el.tagName === 'VIDEO' || el.tagName === 'AUDIO') {
      mediaQuietUntil.set(el, Date.now() + 1000);
      if (Math.abs(el.currentTime - m.time) > 1) el.currentTime = m.time;
      if (m.state === 'play') el.play().catch(() => {}); else el.pause();
    }
  }

  // ---------- strip: every slide as a small picture, for the slide strip at the bottom ----------
  // Only the "strip" copy of the deck does this. It moves the slides into a row of thumbnails.
  // Click a thumbnail to go to that slide. Drag a thumbnail to change the order.
  function buildStrip() {
    const all = slides();
    if (!all.length) return;
    const active = all[currentIndex()] || all[0];
    const W = active.offsetWidth || 1600, H = active.offsetHeight || 900;
    // A column of thumbnails down the left, like Keynote. They grow and shrink with the column's width.
    const fitStrip = () => document.documentElement.style.setProperty('--k', Math.max(60, innerWidth - 46) / W);
    fitStrip(); addEventListener('resize', fitStrip);
    const css = document.createElement('style');
    css.textContent = `
      html, body { overflow-y: auto !important; overflow-x: hidden !important; height: auto !important; background: #f7f7f8 !important; margin: 0 !important; }
      body > :not(#lectern-strip) { display: none !important; }
      #lectern-strip { display: flex; flex-direction: column; gap: 12px; padding: 6px 12px 16px 6px; }
      .lectern-thumb { display: flex; align-items: flex-start; gap: 6px; cursor: pointer; user-select: none; -webkit-user-select: none; }
      .lectern-thumb .pic { position: relative; width: calc(${W}px * var(--k)); height: calc(${H}px * var(--k)); overflow: hidden; border-radius: 8px;
        box-shadow: 0 1px 2px rgba(0,0,0,.06), 0 4px 12px rgba(0,0,0,.08); outline: 0 solid #f26b1d; outline-offset: 2px; }
      .lectern-thumb.here .pic { outline-width: 3px; }
      .lectern-thumb.dragging { opacity: .35; }
      .lectern-thumb .pic > * { position: absolute !important; inset: auto !important; left: 0 !important; top: 0 !important;
        width: ${W}px !important; height: ${H}px !important; transform: scale(var(--k)) !important; transform-origin: 0 0 !important;
        opacity: 1 !important; visibility: visible !important; pointer-events: none !important; transition: none !important; }
      .lectern-thumb .pic .in, .lectern-thumb .pic .step, .lectern-thumb .pic .fragment { opacity: 1 !important; transform: none !important; visibility: visible !important; }
      .lectern-thumb .num { order: -1; flex: none; width: 22px; font: 500 11px -apple-system, system-ui, sans-serif; color: #8a8a8f; text-align: right; padding-top: 2px; }
      .lectern-thumb.here .num { color: #111; font-weight: 600; }`;
    document.head.appendChild(css);
    const strip = document.createElement('div');
    strip.id = 'lectern-strip';
    all.forEach((slide, i) => {
      if (getComputedStyle(slide).display === 'none') slide.style.setProperty('display', 'block', 'important');
      const t = document.createElement('div'); t.className = 'lectern-thumb'; t.dataset.old = i;
      const pic = document.createElement('div'); pic.className = 'pic';
      const num = document.createElement('div'); num.className = 'num';
      pic.append(slide); t.append(pic, num); strip.append(t);
    });
    document.body.append(strip);
    renumber();
    quiet(strip);

    // Drag with the pointer; a short press without moving is a click (go to that slide).
    let drag = null;
    strip.addEventListener('pointerdown', e => {
      const t = e.target.closest('.lectern-thumb'); if (!t) return;
      drag = { t, y: e.clientY, moved: false };
      t.setPointerCapture(e.pointerId);
    });
    strip.addEventListener('pointermove', e => {
      if (!drag) return;
      if (!drag.moved && Math.abs(e.clientY - drag.y) < 6) return;
      drag.moved = true; drag.t.classList.add('dragging');
      // Scroll near the top or bottom edge, then move the thumbnail next to the one under the pointer.
      if (e.clientY < 40) scrollBy(0, -20); else if (e.clientY > innerHeight - 40) scrollBy(0, 20);
      const over = [...strip.children].find(c => c !== drag.t && (() => { const r = c.getBoundingClientRect(); return e.clientY > r.top && e.clientY < r.bottom; })());
      if (over) { const r = over.getBoundingClientRect(); strip.insertBefore(drag.t, e.clientY > r.top + r.height / 2 ? over.nextSibling : over); renumber(); }
    });
    strip.addEventListener('pointerup', () => {
      if (!drag) return;
      const { t, moved } = drag; drag = null; t.classList.remove('dragging');
      if (moved) post({ type: 'strip-order', order: [...strip.children].map(c => Number(c.dataset.old)) });
      else post({ type: 'strip-jump', index: Number(t.dataset.old) });
    });
  }
  function renumber() {
    const strip = document.getElementById('lectern-strip');
    if (strip) [...strip.children].forEach((c, i) => { c.querySelector('.num').textContent = i + 1; });
  }
  function stripHere(index) {
    const strip = document.getElementById('lectern-strip'); if (!strip) return;
    [...strip.children].forEach(c => c.classList.toggle('here', Number(c.dataset.old) === index));
    const here = strip.querySelector('.here');
    if (here) here.scrollIntoView({ block: 'nearest', inline: 'nearest' });
  }

  function start() {
    if (role === 'strip') { buildStrip(); post({ type: 'ready' }); return; }
    quiet(document);
    // Watch only what matters: slides changing class, steps appearing, and slides being added.
    // Animation changes (inline styles) are ignored, so a busy slide does not slow Lectern down.
    const isSlideish = el => el.nodeType === 1 && (el.matches('section, .slide, .step, .fragment') || !!el.querySelector('section, .slide'));
    new MutationObserver(muts => {
      let relevant = false;
      for (const m of muts) {
        if (m.type === 'childList') {
          m.addedNodes.forEach(n => n.nodeType === 1 && quiet(n.parentElement || document));
          if ([...m.addedNodes, ...m.removedNodes].some(isSlideish)) { outlineDirty = true; relevant = true; }
        } else if (isSlideish(m.target) && m.target.matches('section, .slide, .step, .fragment')) relevant = true;
      }
      if (relevant) reportSoon();
    }).observe(document.body, { subtree: true, childList: true, attributes: true, attributeFilter: ['class', 'hidden', 'aria-current'] });
    report(true);
    post({ type: 'ready' });
  }
  if (document.readyState === 'loading') addEventListener('DOMContentLoaded', start); else start();
})();
