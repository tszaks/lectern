# Other ways to run Lectern

The Mac app is the easiest way. Lectern also runs anywhere Node.js runs, using your browser.

## In a browser (Node.js)

Needs [Node.js](https://nodejs.org) 18 or newer. There are no dependencies to install.

```sh
git clone https://github.com/tszaks/lectern.git
cd lectern
node bin/lectern.js              # opens Home in your browser, with projects in ~/Lectern
node bin/lectern.js ~/my-deck    # or present one folder (or one .html file) directly
```

Options: `--port 4321` and `--no-open`. Set `LECTERN_HOME` to use another projects folder.

In a browser, **Presenter view** opens the slides in a new window: drag it to the projector and press **F**. In **Chrome**, Lectern can place the window on the second screen for you after you click **Allow** once (Safari does not let web pages do this).

## On a website (for example Vercel)

You can add a presenter view to a deck that is already published as a website:

```sh
node bin/lectern.js export path/to/deck-folder
```

This adds a `presenter/` folder to the deck. Publish the deck as usual, then open `https://your-site/presenter/`. On a website, notes come from the deck's HTML (`<aside class="notes">`); notes typed there are kept in that browser only, and slide order cannot be saved.
