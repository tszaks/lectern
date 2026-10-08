# Lectern

A small, open-source Mac app for presenting **HTML slide decks** (or slide images) with a real presenter view and speaker notes.
Lectern does not edit slides. You, or an AI agent, make the deck; Lectern shows it, full screen or with a presenter view.

**Download:** get `Lectern.zip` from the [latest release](../../releases/latest), open it, and drag **Lectern** to Applications.
It is signed and notarized by Apple, so it opens like any Mac app. It runs on Intel and Apple-silicon Macs with macOS 12 or newer.

## How it works

1. **Home** — open the app to your projects. Click **New project**, **Open…** an existing deck, or click a recent project.
2. **Project** — slide thumbnails down the left (click to go to a slide, drag to reorder), the slide large, and its notes underneath.
   A new project starts empty: import a deck folder, an HTML file, or slide images.
3. **▶ Present** — choose how:
   - **Presenter view**: the slides go full screen on the TV or projector, and your Mac shows the current slide, the next slide, your notes and a timer.
     Lectern finds the second screen on its own (and moves the slides there if you plug it in later).
   - **Full screen**: the slides fill this screen.
   Press **Esc** (or **End**) to go back to the project.

While presenting:

| Key | Action |
| --- | --- |
| → ↓ Page Down Space | Next |
| ← ↑ Page Up | Previous |
| B or . | Blank the audience screen |
| + / − | Notes text size |
| Esc | End the presentation |

USB clickers work (they send Page Down / Page Up). Videos (YouTube or `<video>`) play on the audience screen with sound and muted in your view, in sync.
Lectern can turn on Do Not Disturb while you present (one-time setup the first time you start).

## Speaker notes

Notes can live in two places:

1. **In the HTML deck**: `<aside class="notes">…</aside>` inside a slide, or `data-notes="…"` on the slide element. Lectern hides these from the audience.
2. **In `notes.md`** in the project. Lectern keeps one heading per slide, with its number and title:

   ```md
   ## Slide 3 · How are you really doing?

   Pause here. Let the room answer before moving on.
   ```

   Notes typed in Lectern save here. A note in `notes.md` wins over a note in the HTML.

## For AI agents

- An agent can write notes into `notes.md` or the HTML, or edit the slides. Open projects update live.
- The [`mcp/`](mcp/) folder has an MCP server so agents can create decks, read the outline, write notes, reorder slides, take screenshots of slides, and check a deck for problems (content off the slide, broken images, errors).

## Which HTML decks work

Any deck you move through with the keyboard. Lectern does not change the deck; it sends the same key presses to every copy of it.
It finds slides with `.reveal .slides > section`, `section.slide`, `.slide`, or `body > section`, and the current slide from the `active`, `present` or `current` class.
Click-to-reveal steps of any kind stay in sync. Each deck is drawn at 1920×1080 and scaled to fit, so every view matches the projector.

## Other ways to run it

- **In a browser:** `node bin/lectern.js` (Node 18+, no dependencies) opens the same app at `http://localhost:4321`. Present one folder directly with `node bin/lectern.js ~/my-deck`.
- **On a website:** `node bin/lectern.js export <deck folder>` adds a presenter view to the deck's own site at `/presenter/` (for example on Vercel).

## Building the Mac app

```sh
bash mac/build.sh     # dist/Lectern.app (ad-hoc signed, for this Mac)
bash mac/release.sh   # signed with your Developer ID, notarized and stapled; see the top of the script
```

## License

MIT
