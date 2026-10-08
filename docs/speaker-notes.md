# Speaker notes

Only you see notes: in the project and in the presenter view. The audience never does.

## Two places notes can live

### 1. In the deck's HTML

Put an `<aside class="notes">` inside the slide, or a `data-notes` attribute on the slide element:

```html
<section class="slide">
  <h2>Our bodies have two modes.</h2>
  <aside class="notes">Ask who has felt "tired but wired" this week.</aside>
</section>

<section class="slide" data-notes="Keep this one short.">…</section>
```

Lectern hides `aside.notes` from the audience, even if the deck itself does not.

### 2. In `notes.md`

Every project has a `notes.md` file next to the deck (for a single imported HTML file, it is `<file name>.notes.md` beside it). Lectern creates it the first time you open the project, with one heading per slide:

```md
# Speaker notes: Are You Running on Empty?

## Slide 1 · Are you running on empty?

Welcome everyone. Introduce yourself.

## Slide 2 · "Life is good."

Pause after "Is it?"
```

- Keep `## Slide N` at the start of each heading: the number matches notes to slides. The text after the dot is only a label so people and agents can see which slide is which.
- Notes you type in Lectern are saved here.
- **A note in `notes.md` wins** over a note in the HTML. Leave a slide's section empty to use the HTML note.
- Edit the file with any text editor, or let an agent do it. An open Lectern window shows the change within a few seconds.
- When you reorder slides in Lectern, their notes move with them.
