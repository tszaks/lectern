# Changelog

## 0.2.2 — 2026-10-08

- **Clicker keeps working after you click a video.** Clicking a YouTube player used to take the keyboard, so the clicker stopped moving slides. Lectern now takes the keyboard back at once.
- **A video stops when you move to the next slide**, so its sound does not go on under the next slides (as in Keynote).
- **Esc must be pressed twice to end a show** ("Press Esc again to end the show"). Clicker "slideshow" buttons that send Esc can no longer end a talk by accident.
- **⌘Q and closing the window ask first** during a show. ⌘R, All Projects and New Project do nothing during a show, and the back arrow is hidden (each one used to freeze the TV or send it back to slide 1).
- **The notes are read-only during a show**, so a click in them no longer turns the clicker's keys into typing. Edit notes in the project, as before.
- A link on a slide opens once (it used to open twice: once for each copy of the slide).
- New Mac self-test for videos (`LECTERN_SELFTEST_MODE=video`).

## 0.2.1 — 2026-10-08

- Keeps the Mac and its display awake while presenting (the screen no longer goes dark during a long video or discussion).
- No question pops up when a show starts. Set up Do Not Disturb any time from **Lectern → Set Up Do Not Disturb…**.

## 0.2.0 — 2026-10-08

- **Send a project as one file.** Export a project as a `.lectern` file (slides, images, fonts and notes); double-click it on another Mac to open it in Lectern.
- **Export** button in the project, **File → Export Project…** (⌘E). **Open…** accepts `.lectern` files too.

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
