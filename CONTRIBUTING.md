# Contributing

Thanks for helping. Lectern is small on purpose: plain web pages, a dependency-free Node server, and a thin native Mac app.

## Run it

```sh
node bin/lectern.js        # in a browser, Node 18+
bash mac/build.sh          # the Mac app (Xcode command line tools), then open dist/Lectern.app
```

## Before you open a pull request

- `node --check bin/lectern.js app/adapter.js`
- Try the whole flow by hand: Home → open or create a project → reorder a slide → **Present → Presenter view** → clicker keys → **End**; and **Present → Full screen** → **Esc**.
- If you changed a route in `bin/lectern.js`, make the same change in `mac/Sources/Server.swift`.
- Run the Mac app self-test (see [AGENTS.md](AGENTS.md)).
- Use a temporary projects folder for testing: `LECTERN_HOME=$(mktemp -d)`.

## Releasing (maintainers)

1. Put your signing details in `~/.lectern-release.env` (see the top of `mac/release.sh`).
2. `bash mac/release.sh` builds, signs with your Developer ID, notarizes with Apple, staples, and zips to `dist/Lectern.zip`.
3. Create a new GitHub release (a new version tag each time) and attach `dist/Lectern.zip`.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
