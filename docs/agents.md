# Agents and MCP

Lectern is designed so an AI agent can do the heavy lifting (writing the deck, the notes, the order) while Lectern presents.

## What an agent can do without any tools

- **Write or fix a deck** that follows the [deck format](deck-format.md).
- **Write notes** in `notes.md` (one `## Slide N · title` section per slide) or as `<aside class="notes">` in the HTML. See [Speaker notes](speaker-notes.md).
- An open Lectern window reloads when the deck changes and keeps the same slide, and shows `notes.md` changes within a few seconds.

Projects are folders in `~/Lectern` (or links to folders elsewhere).

## The MCP server

The [`mcp/`](../mcp) folder has an MCP server that lets an agent build decks and test them in Lectern for real, with a headless Google Chrome.

### Install

Needs Node.js 18+ and Google Chrome.

```sh
cd mcp && npm install
claude mcp add lectern -- node "$(pwd)/server.js"
```

Other MCP clients:

```json
{ "mcpServers": { "lectern": { "command": "node", "args": ["/path/to/lectern/mcp/server.js"] } } }
```

Set `LECTERN_HOME` to use a library folder other than `~/Lectern`.

### Tools

| Tool | What it does |
| --- | --- |
| `lectern_start` | Make sure a Lectern server is running for a library (the other tools start one for you). |
| `list_decks` | List the decks in the library. |
| `create_deck` | Write a new deck: `name`, `files: [{ path, content }]`. Will not overwrite unless `overwrite: true`. |
| `get_outline` | Slide count, and each slide's number, title, and notes. |
| `set_notes` | Set one slide's notes (saved in `notes.md`). |
| `reorder_slides` | New order as old slide numbers, for example `[1, 3, 2, 4]`. Notes move with the slides. |
| `screenshot_slides` | 1920×1080 pictures of slides; `step: "all"` also shows each click-to-reveal step. |
| `check_deck` | Walk every slide; report console errors, failed requests, content outside the slide, broken images, and slides with no notes. |
| `present_url` | The presenter page address. |

Slide numbers start at 1.

### A good loop for an agent

1. `create_deck` with an `index.html` that follows the [deck format](deck-format.md).
2. `check_deck`, then fix anything it reports.
3. `screenshot_slides` and look at every slide.
4. `get_outline`, then `set_notes` for each slide.
5. Hand the person the project name. They open it in Lectern and present.

## HTTP API (local)

The Lectern server (the Mac app, or `node bin/lectern.js`) listens on `127.0.0.1` only.

| Request | Does |
| --- | --- |
| `GET /api/decks` | List projects: name, kind (`html` / `images` / `empty`), modified time |
| `POST /api/new/<name>` | Create an empty project |
| `PUT /api/upload/<name>/<path>` | Write one file into a project (body = file) |
| `GET /api/notes/<name>` | Notes and slide labels from `notes.md` |
| `PUT /api/notes/<name>` | `{ "slide": 3, "text": "…" }` saves one note |
| `PUT /api/order/<name>` | `{ "order": [0, 2, 1, …] }` reorders slides (0-based) |
| `GET /api/version/<name>` | Changes when the deck or notes change |
