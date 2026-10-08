# AGENTS.md

Guidance for AI coding agents working on the Lectern code itself. (To write a *deck* for Lectern, read [docs/deck-format.md](docs/deck-format.md) instead.)

## What this is

A Mac app (Swift, AppKit, WebKit) and a Node.js server that both serve the same web pages in `app/`. Lectern presents HTML slide decks with a presenter view. It never edits slide content, except reordering slides when the person asks.

## Layout

- `app/` — the web pages, shared by both servers. Plain HTML, CSS and JavaScript; no build step, no dependencies.
  - `adapter.js` is injected into every copy of a deck. It must work with any deck that follows the deck format.
  - `presenter.html` has two modes: the project view (default) and presenting (`body.presenting`).
- `bin/lectern.js` — the Node.js server. **No dependencies.** Keep it that way.
- `mac/Sources/Server.swift` — the same HTTP routes in Swift. **Any route added or changed in `bin/lectern.js` must be ported here too.**
- `mac/` — `build.sh` (local build), `release.sh` (Developer ID signing and notarization; private details come from `~/.lectern-release.env`, never from the repo).
- `mcp/` — the MCP server (Node.js; `@modelcontextprotocol/sdk`, `playwright-core`).
- `examples/` — example decks. `docs/` — documentation and README images.

## Commands

```sh
node bin/lectern.js --no-open --port 4321          # run the server (projects in ~/Lectern, or $LECTERN_HOME)
node --check bin/lectern.js app/adapter.js         # syntax check
bash mac/build.sh                                  # build dist/Lectern.app
LECTERN_HOME=/tmp/lib LECTERN_SELFTEST=<project> LECTERN_SELFTEST_OUT=/tmp/out \
  dist/Lectern.app/Contents/MacOS/Lectern          # end-to-end self-test of the Mac app; results in /tmp/out/results.json
```

## Rules

- **Test the whole flow a person clicks through,** with real input (Playwright with `channel: 'chrome'` from `mcp/node_modules` works), not only the piece you changed. Look at screenshots. Many past bugs only showed up in the full flow (a hidden view that drew nothing, a menu that a click inside a slide did not close).
- **Use a temporary library** (`LECTERN_HOME=$(mktemp -d)`) for tests. Never write into a real project or `~/Lectern`.
- **Keep the deck untouched.** Views drive decks by sending key presses; do not depend on a deck's internal names. Prefer detecting changes (see `pressAndSee` in `adapter.js`) over guessing class names.
- **Every view renders the deck at 1920×1080 and scales it.** Never size a deck view with `display: none`; hide it off screen instead, or the deck measures 0 and draws nothing.
- **Never put secrets in the repo.** Signing and notary details live in `~/.lectern-release.env`.
- Comments and UI text are short and plain.
- The design: white, light gray and black, one orange accent (`#f26b1d`), SF Pro (the timer uses SF Pro Rounded, heavy).
