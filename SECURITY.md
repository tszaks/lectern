# Security policy

## Supported versions

Only the latest release of Lectern gets security fixes.

| Version | Supported |
|---|---|
| 0.2.x (latest) | Yes |
| Older | No |

## Reporting a vulnerability

Please report security problems privately, not in a public issue.

Use GitHub private vulnerability reporting: open the **Security** tab of this repository and choose **Report a vulnerability**. If that is not available to you, email tyler@szakacsmedia.com.

Please include:

- What you found and what an attacker could do with it.
- Steps to reproduce, or a sample deck that triggers it.
- Your macOS version and Lectern version (Lectern > About Lectern).

You can expect a first reply within a few days. Lectern is maintained by a small team, so a fix may take longer, but you will get updates.

## What counts

Lectern runs decks, which are web pages that can contain script. These areas matter most:

- The local server (`127.0.0.1`, in the Mac app and in `bin/lectern.js`): anything that lets another website or another user on the network read or write your projects through it.
- The self-updater (`mac/Sources/Updater.swift`): anything that lets it install an app that is not signed by the developer of the running one.
- Export and import of `.lectern` files: path tricks that write outside the project folder.
- The MCP server (`mcp/`): it can create and change decks in the library folder and drive a headless Chrome. It should never read or write outside that folder.

A deck is trusted content that you chose to open. A deck that runs its own script inside its own slides is not a vulnerability.

Lectern makes one kind of network request of its own, the update check. See the [README FAQ](README.md#faq).
