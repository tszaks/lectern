# Lectern MCP server

Lets an AI agent make HTML slide decks and test them live in Lectern. It starts the normal Lectern server for a library folder (default `~/Lectern`, or `$LECTERN_HOME`) and uses the Google Chrome on your Mac, headless, to look at the real deck.

Needs Node 18+ and Google Chrome. Install once: `cd mcp && npm install`.

## Register it in Claude Code

```sh
claude mcp add lectern -- node /path/to/lectern/mcp/server.js
```

Or put this in an MCP config file:

```json
{
  "mcpServers": {
    "lectern": {
      "command": "node",
      "args": ["/path/to/lectern/mcp/server.js"]
    }
  }
}
```

To use another library folder, add `"env": { "LECTERN_HOME": "/path/to/library" }`, or pass `library` to `lectern_start`.

## Tools

| Tool | What it does |
| --- | --- |
| `lectern_start` | Make sure a Lectern server runs for a library. Reuses one that runs. The other tools start it for you. |
| `list_decks` | List the decks in the library. |
| `create_deck` | Write a new deck folder (`name`, `files: [{path, content}]`). Will not overwrite unless `overwrite: true`. Refuses paths that leave the folder. |
| `get_outline` | Slide count, and each slide's number, title and notes (notes.md wins over HTML notes). |
| `set_notes` | Set the notes for one slide (saved in `notes.md`). |
| `reorder_slides` | New order, as old slide numbers: `[1,3,2,4]`. Notes move with the slides. |
| `screenshot_slides` | 1920x1080 pictures of slides (PNG on disk, small JPEG returned). `step: "all"` also shows each click-to-reveal step. |
| `check_deck` | Walk every slide and report console errors, failed requests, content outside the frame, missing images, and slides with no notes. |
| `present_url` | The presenter page address. |

Slide numbers start at 1. Screenshots are saved under the system temp folder, not in the deck.
