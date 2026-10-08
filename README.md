# Lectern

A small, open-source presenter for slide decks made of **HTML or images**.
Lectern does not edit slides. You (or an AI agent) make the slides; Lectern shows them, full screen, with a presenter view and speaker notes.

- **Audience window**: the slides, full screen on the projector (press **F**).
- **Presenter window**: the current slide, the next slide, your notes, a timer, and the clock.
- **USB clickers work**: Page Down / Page Up, the arrow keys, and the "blank screen" button (B or .).
- **Notes text size**: A− / A+ buttons, or the − and + keys.
- **Interactive HTML slides stay in sync**: a click in one window happens in the other window too.
- **Light**: no install and no dependencies. It uses the browser that is already on the computer (Safari or Chrome). There is no Electron.

## Use it

You need Node.js 18 or newer.

```sh
node bin/lectern.js            # open your library (~/Lectern)
node bin/lectern.js ~/my-deck  # or present one folder directly
```

In the library, drop a folder onto the page. The folder can hold:

- an **HTML deck** with its images and fonts (Lectern uses `index.html`, or the first `.html` file), or
- **slide images** (`01.png`, `02.png`, … in name order). Export from PowerPoint or Keynote as images to use them here.

Click **Present**, then **Open audience window**. Drag that window to the projector and press **F**.

| Key | Action |
| --- | --- |
| → ↓ Page Down Space | Next |
| ← ↑ Page Up | Previous |
| B or . | Blank the audience screen |
| + / − | Notes text size |
| F | Full screen |
| Click the timer | Start or pause. It starts on the first slide change. Double-click to reset. |

## Speaker notes (for people and agents)

Notes can live in two places:

1. **In the HTML deck**: `<aside class="notes">…</aside>` inside a slide, or `data-notes="…"` on the slide element. Lectern hides these from the audience.
2. **In `notes.md`** in the deck folder. Lectern makes this file when you first present the deck. It has one heading per slide with the slide number and title:

   ```md
   ## Slide 3 · How are you really doing?

   Pause here. Let the room answer before moving on.
   ```

   Notes that you type in the presenter view save here. A note in `notes.md` wins over a note in the HTML.

To have an agent add notes, tell it the deck folder. It reads `notes.md` to see which slide is which and writes the notes under each heading, or it writes `<aside class="notes">` into the HTML. Open presenter windows show the change within a few seconds. If the agent changes the slides, the windows reload and stay on the same slide.

## What HTML decks work

Any deck that you move through with the keyboard. Lectern does not change the deck. It sends the same key presses to every copy of the deck. It finds slides with `.reveal .slides > section`, `section.slide`, `.slide`, or `body > section`, and the current slide from the `active`, `present`, or `current` class. Click-to-reveal steps (`.step` / `.shown`, or reveal.js `.fragment`) stay in sync.

Each deck is drawn at 1920×1080 and scaled to fit the window, so the projector and the presenter view always match.

Try `node bin/lectern.js examples/demo`.

## License

MIT
