# Deck format

This is the contract between a deck and Lectern. Follow it and the deck will work in Lectern: in the project view, the presenter view, the thumbnails, and on the audience screen, all in sync.

It is written for people and for AI agents generating decks. A complete, working example is [`examples/welcome/index.html`](../examples/welcome/index.html).

## Rules

1. **One HTML file.** The deck is an `.html` file. If the project folder holds several, Lectern uses `index.html`, or else the first one by name. Images, fonts and scripts go next to it and are linked with **relative paths** (`img/photo.jpg`, not `/img/photo.jpg` and not `file:///…`).

2. **Slides are elements Lectern can find.** Lectern looks for slides with the first of these selectors that matches anything:
   1. `.reveal .slides > section` (reveal.js)
   2. `section.slide`
   3. `.slide`
   4. `body > section`

   Use `<section class="slide">` unless you have a reason not to. Make slides **siblings** (one after another), not nested inside each other.

3. **The current slide is marked.** Exactly one slide has the class `active` (or `present` / `current`, or `aria-current="true"`). Lectern reads this class to know where the deck is.

4. **The keyboard moves the deck.** The deck must handle `keydown` on `window` (or `document`):

   | Key | Must do |
   | --- | --- |
   | `ArrowRight`, `ArrowDown`, `PageDown`, `' '` (Space), `Enter` | Next step, or next slide |
   | `ArrowLeft`, `ArrowUp`, `PageUp`, `Backspace` | Previous |
   | `Home` / `End` | First / last slide |

   Lectern drives every copy of the deck by sending these key presses, so the deck must not ignore key events it did not create itself (do not check `event.isTrusted`).

5. **Click-to-reveal steps add a class.** A part shown on a later click gets a class when it appears. Use `class="step"` and add `shown` when revealed (reveal.js uses `fragment` and `visible`). "Next" reveals the next hidden step first and moves to the next slide only when the slide has none left. Lectern detects any change a key press makes, so other class names also work, but `step` / `shown` is the convention.

6. **Fixed stage, scaled.** Design every slide for one size (1600×900 or 1920×1080) and scale the whole stage to fit the window, keeping 16:9. Lectern draws every view at 1920×1080 and scales the result, so a deck that scales itself looks identical on the projector, in the presenter view and in the thumbnails.

7. **Notes** go in `<aside class="notes">` inside the slide, or `data-notes="…"` on it. See [Speaker notes](speaker-notes.md).

8. **No content between slides.** Only whitespace and HTML comments between one slide's closing tag and the next slide's opening tag. This lets Lectern reorder slides safely by moving whole `<section>` blocks.

## Recommended

- Keep each deck self-contained: local fonts and images, no build step.
- Animate with CSS transitions on the `active` and `shown` classes.
- Video: use a YouTube embed with `enablejsapi=1` (for example `https://www.youtube-nocookie.com/embed/VIDEO_ID?enablejsapi=1`), or a `<video>` element. Lectern then plays the video in every view in sync. Other players play on the audience screen only.
- Put on-screen controls (arrow buttons, a full-screen button) behind a mouse-move check, so they do not show on the projector.

## Minimal deck

```html
<!doctype html>
<html><head><meta charset="utf-8"><title>My talk</title>
<style>
  html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
  #stage { position: fixed; left: 50%; top: 50%; width: 1600px; height: 900px;
           transform: translate(-50%, -50%) scale(var(--s, 1)); background: #fff; }
  .slide { position: absolute; inset: 0; padding: 100px; display: none; }
  .slide.active { display: block; }
  .step { opacity: 0; } .step.shown { opacity: 1; }
  aside.notes { display: none; }
</style></head>
<body><div id="stage">
  <section class="slide active"><h1>Hello</h1><aside class="notes">Say hi.</aside></section>
  <section class="slide"><h1>Two points</h1><p class="step">One</p><p class="step">Two</p></section>
</div>
<script>
  const stage = document.getElementById('stage');
  const fit = () => stage.style.setProperty('--s', Math.min(innerWidth / 1600, innerHeight / 900));
  addEventListener('resize', fit); fit();
  const slides = [...document.querySelectorAll('.slide')]; let cur = 0;
  const show = i => { slides[cur].classList.remove('active'); cur = Math.max(0, Math.min(slides.length - 1, i)); slides[cur].classList.add('active'); };
  const next = () => { const s = slides[cur].querySelector('.step:not(.shown)'); s ? s.classList.add('shown') : show(cur + 1); };
  const prev = () => { const s = [...slides[cur].querySelectorAll('.step.shown')].pop(); s ? s.classList.remove('shown') : show(cur - 1); };
  addEventListener('keydown', e => {
    if (['ArrowRight', 'ArrowDown', 'PageDown', ' ', 'Enter'].includes(e.key)) { e.preventDefault(); next(); }
    else if (['ArrowLeft', 'ArrowUp', 'PageUp', 'Backspace'].includes(e.key)) { e.preventDefault(); prev(); }
    else if (e.key === 'Home') show(0); else if (e.key === 'End') show(slides.length - 1);
  });
</script></body></html>
```

## Slide images instead of HTML

A project can also be a folder of images (`.png`, `.jpg`, `.jpeg`, `.gif`, `.webp`, `.avif`, `.svg`). They are shown in name order (`01.png`, `02.png`, … `10.png`). Export slides from Keynote or PowerPoint as images to present them this way. Notes for image projects go in `notes.md`.

## Check a deck

With the [MCP server](agents.md), run `check_deck`: it walks every slide and reports content outside the slide, broken images, console errors, failed requests, and slides without notes.
