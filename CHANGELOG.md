# Changelog

## 0.1.1 — 2026-10-08

- The presenter view notices when the slides window closes (the status goes back to "Audience not open").
- Documentation, example deck, and files for AI tools (`llms.txt`, `AGENTS.md`).

## 0.1.0 — 2026-10-08

First release.

- Native Mac app (1.4 MB, Apple silicon and Intel, macOS 12+), signed and notarized.
- Home with projects: new, open (links to the original), recent, drag a folder in.
- Project view: slide thumbnails, the slide, and notes; reorder slides by dragging (lifted copy, dashed landing outline), saved safely with a backup.
- Present: **Presenter view** (slides on the second screen, Now / Next / notes / timer on the Mac) or **Full screen**; Esc or End returns to the project.
- Finds the second screen on its own; USB clickers; blank screen (B); notes text size.
- Interactive slides, click-to-reveal steps and videos stay in sync across views.
- Speaker notes in the HTML or in `notes.md`, shown live as they change.
- Optional Do Not Disturb while presenting.
- Node.js server (no dependencies), `lectern export` for websites, and an MCP server for AI agents.
