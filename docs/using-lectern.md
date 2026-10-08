# Using Lectern

## Home

Home lists your projects, the most recently edited first. Each row shows whether the project is an HTML deck or slide images, and when it was last edited.

| Action | How |
| --- | --- |
| New project | **New project** button, or **File → New Project** (⌘N) |
| Open a deck you have | **Open…** button, **File → Open…** (⌘O) or **File → Import…** (⌘I): choose an HTML file or a folder |
| Import by dragging | Drop a folder or an HTML file on the window, or on Lectern's icon in the Dock |
| Open a project | Click it. **File → Open Recent** lists recent projects. |
| Back to Home | The **‹** arrow at the top left, or **File → All Projects** (⇧⌘L) |

Lectern reopens the project you had open last time.

**Where projects live.** Projects are folders in `~/Lectern`. A deck opened with **Open…** is a link to your original folder or file, so it stays where it is and Lectern sees every change. Projects you create with **New project** are real folders inside `~/Lectern`.

## Send a project

A `.lectern` file is a whole project in one file: the deck, its images and fonts, and `notes.md`.

- **Export:** open the project and click **Export** (or **File → Export Project…**, ⌘E). Choose where to save it (the Desktop by default).
- **Send** the file however you like: Messages, email, AirDrop, a USB stick.
- **Open:** double-click the `.lectern` file. Lectern opens it as a new project in `~/Lectern` and shows it. Opening the same file twice makes a second copy ("Name 2"); nothing is overwritten.

Under the hood a `.lectern` file is a zip of the project folder, so you can also rename one to `.zip` to look inside. Hidden files (such as a `.git` folder) are left out.

## Inside a project

- **Thumbnails** (left): click to go to a slide. The current slide has an orange outline.
- **The slide** (middle): exactly what the audience will see, scaled to fit.
- **Notes** (bottom): notes for the current slide. Type to edit; they save on their own. **A− / A+** (or **−** and **+**) change the text size.
- **← / →** under the slide, or the arrow keys, move through slides and click-to-reveal steps.

### Reorder slides

Drag a thumbnail up or down. The slide lifts and follows the pointer, a dashed orange outline shows where it will land, and the other slides move out of the way. Let go, then click **Save order** at the top of the thumbnails, or **Cancel**. Press **Esc** while dragging to cancel.

Saving rewrites the order of the slides in the deck file. Their content does not change, a backup of the old file is kept in the project's `.lectern-backup` folder, and notes move with their slides. If Lectern cannot safely tell the slides apart in the HTML, it changes nothing and says why.

## Presenting

Click **▶ Present** (top right) and choose:

### Presenter view

- With a **second screen** (TV, projector, monitor): the slides go full screen on it, and your Mac shows the presenter view full screen. Lectern tells your Mac's own screen apart from the others by itself. If you plug in the screen after you start, the slides move to it.
- With **one screen**: the slides open in their own window, in front. Use this to rehearse.

The presenter view shows **Now** (the current slide), **Next** (a picture of the next slide), your **notes**, the **timer** (it starts at 0:00 when you start presenting; click it to pause, double-click to reset), the clock, and the audience status:

| Status | Meaning |
| --- | --- |
| ○ Audience not open | No slides window is showing. |
| ● Audience in sync | The audience sees the same slide and step as you. |
| ● Audience on slide N (orange) | They differ. Click **Fix** to bring them back in line. |

Click **End** or press **Esc** to stop. The slides window closes and you return to the project.

### Full screen

The slides fill this screen. Use the arrow keys or a clicker. Press **Esc** to return to the project.

### Keys

| Key | Action |
| --- | --- |
| → ↓ Page Down Space Return | Next slide, or the next click-to-reveal step |
| ← ↑ Page Up Backspace | Previous |
| Home / End | First / last slide |
| B or . | Blank the audience screen; press again to show it |
| + / − | Bigger / smaller notes |
| F | Full screen (slides window) |
| Esc | End the presentation |

**Clickers.** USB and Bluetooth presentation clickers act like a small keyboard (Page Down / Page Up, sometimes B), so they work without setup. Page Down and Page Up work even while you are typing in the notes.

### Video

Videos on slides (YouTube players and `<video>`) play on the audience screen with sound and in your Now view muted, in sync: play, pause and jumps in one happen in the other. Other embedded players (for example TED's own player) cannot be controlled, so they play on the audience screen only.

### Do Not Disturb

macOS has no switch apps can use for Focus, so Lectern uses two small Shortcuts. The first time you start presenting, Lectern offers to set them up: click **Set Up**, then **Add Shortcut** twice. After that, Lectern turns Do Not Disturb on when you start presenting and off when you end (only if Lectern turned it on). You can run the setup again from **Lectern → Set Up Do Not Disturb…**.
