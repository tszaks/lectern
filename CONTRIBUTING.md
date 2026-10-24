# Contributing

Thanks for helping. Lectern is small on purpose: plain web pages, a dependency-free Node server, and a thin native Mac app. The bar for a change is: does it keep Lectern light, and does it leave the person's slides untouched?

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before you start

- For bugs, open an issue with the template.
- For features, open an issue first and describe the problem you want to solve.
- Small fixes (typos, clear bugs) can go straight to a pull request.
- Security problems go through [SECURITY.md](SECURITY.md), not a public issue.

## Setup and run

You need Node 18+ for the server and the MCP server, and the Xcode command line tools for the Mac app. There is no package install for the main app.


```sh
node bin/lectern.js        # in a browser, Node 18+
bash mac/build.sh          # the Mac app (Xcode command line tools), then open dist/Lectern.app
```

## Code style

- **Match the surrounding code.** Same naming, same comment density, same idiom as the file you are editing. There is no formatter.
- Keep `bin/lectern.js` free of dependencies, and keep the web pages in `app/` plain HTML, CSS and JavaScript with no build step.
- Comments and UI text are short and plain.

## Tests

`node --check bin/lectern.js app/adapter.js` is the syntax check CI runs. There is also a browser test for hold-to-end and notes in `test/hold-to-end.test.mjs`. It needs Playwright installed outside the repo; the steps are at the top of that file.

## Pull request checklist

- `node --check bin/lectern.js app/adapter.js`
- Try the whole flow by hand: Home → open or create a project → reorder a slide → **Present → Presenter view** → clicker keys → **End**; and **Present → Full screen** → **Esc**.
- If you changed a route in `bin/lectern.js`, make the same change in `mac/Sources/Server.swift`.
- Run the Mac app self-test (see [AGENTS.md](AGENTS.md)).
- Use a temporary projects folder for testing: `LECTERN_HOME=$(mktemp -d)`.
- Add a line under `[Unreleased]` in [CHANGELOG.md](CHANGELOG.md) for anything a user would notice.
- Do not put signing details, tokens or personal paths in the repo.

## Releasing (maintainers)

1. Put your signing details in `~/.lectern-release.env` (see the top of `mac/release.sh`).
2. `bash mac/release.sh` builds, signs with your Developer ID, notarizes with Apple, staples, and zips to `dist/Lectern.zip`.
3. Create a new GitHub release (a new version tag each time) and attach `dist/Lectern.zip`.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
