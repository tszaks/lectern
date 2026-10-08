# Architecture

Lectern is a small local web server plus a few web pages, wrapped in a native Mac app.

```
mac/        Swift + AppKit + WebKit app: windows, screens, full screen, Do Not Disturb, a local HTTP server
bin/        lectern.js: the same server for Node.js (no dependencies), and `lectern export`
app/        the pages both servers serve
  home.html       Home: projects
  presenter.html  a project, the presenter view, and the Present menu
  audience.html   the slides window
  adapter.js      injected into every copy of a deck
mcp/        MCP server for AI agents
examples/   example decks
```

## How a deck is driven

Lectern never rewrites a deck to present it. Each view (audience, current slide, next slide, thumbnails) loads its own copy of the deck in an iframe, and Lectern injects `adapter.js` into each copy.

- The adapter **finds the slides** and the current one (see the [deck format](deck-format.md)) and reports the slide number, the click-to-reveal step count, titles and notes.
- **Key presses** (keyboard or clicker) are caught by the adapter and sent to every copy as the same key, so all copies move together. A `BroadcastChannel` connects the presenter and the slides window.
- **Clicks** on interactive slides are replayed in the other copies by element path.
- **Jumping** to a slide presses keys until the deck is there. A press that changes nothing in the page means the deck is at its end, so any reveal scheme works.
- **Video**: YouTube players (via their iframe API) and `<video>` elements report play, pause and seek; the other copies follow, muted except the audience.
- The **Next** copy is frozen (no animations). The **thumbnails** copy moves every slide into a scaled column.

Every view draws the deck in a 1920×1080 frame scaled to fit, so all views match.

## Files on disk

- Projects: folders (or links) in `~/Lectern` (`LECTERN_HOME`).
- `notes.md` per project, one `## Slide N · title` section per slide.
- Reordering rewrites the deck's top-level `<section>` blocks; the old file goes to `.lectern-backup/`.

## The Mac app

`mac/Sources/`: `main.swift` (windows, screens, menus, title bar), `Server.swift` (the HTTP server, same routes as `bin/lectern.js`), `Focus.swift` (Do Not Disturb through Shortcuts), `SelfTest.swift` (an end-to-end self-test, run with `LECTERN_SELFTEST=<project>`).
