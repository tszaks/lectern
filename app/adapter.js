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
    (role === 'preview' ? '*,*::before,*::after{transition-duration:0s!important;transition-delay:0s!important}' : '');
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
  const shownSteps = slide => slide ? slide.querySelectorAll('.step.shown, .fragment.visible').length : 0;

  let lastSent = '';
  function report(force) {
    const all = slides();
    const index = currentIndex();
    const state = {
      type: 'state', index, count: all.length, title: document.title,
      notes: all.map(notesFor), labels: all.map(labelFor), images: all.map(imageOf), steps: shownSteps(all[index]),
    };
    const key = JSON.stringify(state);
    if (force || key !== lastSent) { lastSent = key; post(state); }
  }
  let pending = null;
  const reportSoon = () => { clearTimeout(pending); pending = setTimeout(report, 30); };

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
    // Start clean, so earlier visits do not leave steps showing.
    document.querySelectorAll('.step.shown').forEach(el => el.classList.remove('shown'));
    document.querySelectorAll('.fragment.visible').forEach(el => el.classList.remove('visible'));
    press('Home');
    for (let i = 0; i < 1000 && currentIndex() < n; i++) {
      const before = currentIndex(), stepsLeft = hasHiddenSteps(slides()[before]);
      press('ArrowRight');
      if (currentIndex() === before && !stepsLeft) break; // deck stopped moving
    }
    for (let i = 0; i < steps && currentIndex() === n && hasHiddenSteps(slides()[n]); i++) press('ArrowRight');
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
    if (!e.isTrusted) return reportSoon(); // our own replayed key: let the deck act on it
    const t = e.target;
    if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return;
    if (e.metaKey || e.ctrlKey || e.altKey) return;
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
    if (!e.isTrusted || role === 'preview') return;
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
    reportSoon();
  });
  addEventListener('hashchange', reportSoon);

  // Only the audience plays sound and embedded video. The presenter copies stay quiet.
  function quiet(root) {
    if (role === 'audience') return;
    root.querySelectorAll('video, audio').forEach(m => { m.muted = true; });
    root.querySelectorAll('iframe').forEach(f => {
      if (!f.srcdoc) f.srcdoc = '<body style="margin:0;display:grid;place-items:center;height:100vh;background:#111;color:#999;font:600 28px system-ui">Plays on the audience screen</body>';
    });
  }

  function start() {
    quiet(document);
    new MutationObserver(muts => {
      for (const m of muts) if (m.type === 'childList') m.addedNodes.forEach(n => n.nodeType === 1 && quiet(n.parentElement || document));
      reportSoon();
    }).observe(document.body, { subtree: true, childList: true, attributes: true, attributeFilter: ['class', 'style', 'hidden', 'aria-current'] });
    report(true);
    post({ type: 'ready' });
  }
  if (document.readyState === 'loading') addEventListener('DOMContentLoaded', start); else start();
})();
