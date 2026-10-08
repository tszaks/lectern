# Troubleshooting

**The slides do not go to my TV or projector.**
Check the screen is connected and set to **extend** (not mirror) in System Settings → Displays. Lectern puts the slides on the screen that is not your Mac's built-in one. Also turn on System Settings → Desktop & Dock → **Displays have separate Spaces** (the macOS default).

**Start presenting seems to do nothing.**
With one screen, the slides open in their own window in front of the presenter view. If you use Stage Manager, look for it in the strip on the left.

**My clicker does not work.**
Click once inside the Lectern window so it has focus, then try again. Most clickers send Page Down / Page Up, which Lectern handles everywhere.

**The audience screen is on a different slide.**
The status at the top right turns orange. Click **Fix**.

**A video plays only on the audience screen.**
Lectern can sync YouTube players (with `enablejsapi=1`) and `<video>` elements. Other players, such as TED's, cannot be controlled from outside, so they play on the audience screen only.

**Save order says it did not change anything.**
Lectern only reorders a deck when each slide is a separate block with nothing but whitespace or comments between slides. See rule 8 in the [deck format](deck-format.md). Lectern refused so it would not break the deck.

**Images or fonts are missing.**
Import the deck's whole folder, not only the HTML file, and use relative paths in the deck.

**Notes disappear for a slide.**
A note in `notes.md` wins over the HTML. If a slide's section in `notes.md` is empty, the HTML note is used.

Still stuck? [Open an issue](https://github.com/tszaks/lectern/issues).
