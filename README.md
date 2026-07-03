# Focus Familiar — concept demo

A small creature that lives on top of your macOS screen. It is not just a pet:

**it feeds on focus, gets corrupted by distraction, and remembers lost context.**

This repo is a *product concept demo* — a simulated macOS desktop in the browser
that plays a ~2-minute cinematic walkthrough of the idea, plus a sandbox where
you can drive it yourself.

## Run it

```bash
python3 -m http.server 5199 --directory .
# open http://localhost:5199
```

No build step, no dependencies. Plain HTML/CSS/JS.

## What the demo shows

1. **The quiet companion** — the familiar floats in the corner while you code.
2. **Shapeshifting** — it knows *what kind* of work you're doing: shipping code
   earns 🥩 protein, terminal grind smelts ⛓️ iron, papers earn 📖 spellbooks,
   planning docs become 🔮 memory fragments.
3. **Corruption** — open X and it gets dizzy; nine minutes of doomscrolling and
   it's poisoned; frantic tab-switching turns it into a ghost.
4. **Evolution** — a 92-minute deep-work streak levels it up into *Emberling, lv.2*.
5. **Restore my context** — hours later you ask "what was I just doing?" and it
   replays the thread: the file, the fix you made, and the next step you'd planned.
6. **The daily quest map** — your day retold as an RPG: main quest, side quests,
   admin tax, and the distraction pit you fell into.

## Sandbox controls

- click dock apps — deep-work apps feed it, feeds poison it
- rapid app-switching (4 in 5s) — ghost mode
- `R` / click the familiar / `⌥Space` — restore context
- `Q` — quest map · `Esc` — close overlays

## Design intent

Desktop pet × RPG companion × screen-aware memory assistant × ambient
productivity coach. Minimal, charming, high-signal — playful and slightly
mischievous, never corporate.

## Native macOS app (`mac/`)

The real thing — a creature that floats above your actual desktop:

```bash
mac/build.sh                      # builds mac/build/FocusFamiliar.app with swiftc
cp -R mac/build/FocusFamiliar.app "/Applications/Focus Familiar.app"
open "/Applications/Focus Familiar.app"
```

- Transparent, always-on-top, click-through panel (bottom-right, all Spaces);
  never steals focus.
- Watches the frontmost app via NSWorkspace (**no permissions needed**) and
  classifies it: VS Code/Cursor/Claude/Terminal/KiCad/Notion/Preview → deep work;
  X/Steam → distraction.
- **Browser awareness**: reads the active tab URL via AppleScript
  (one-time Automation permission prompt per browser). youtube/x/reddit/小红书/
  bilibili → distraction; arxiv/github/overleaf/colab → deep.
- Menu bar `◐`: switch character (Wisp / Robo-cat / Panda / 暗原子 Dark Atom /
  Beaver), toggle clickable, pause, quit.
- `⌥Space` anywhere: "what was I doing?" — the familiar replays your recent
  app thread (Carbon hotkey, no permissions needed).
- All tracking is local; nothing leaves the machine.

## Files

- `index.html` — desktop shell, familiar SVG, overlays
- `styles.css` — all theming; familiar states are CSS palettes on `[data-state]`
- `js/windows.js` — fake app windows (VS Code, Terminal, KiCad, paper, Notion, X, Shorts)
- `js/familiar.js` — creature state machine, resources, pickups, speech bubble
- `js/demo.js` — the 7-scene scripted concept demo
- `js/questmap.js` — daily quest map overlay
- `js/main.js` — app switching, sandbox focus engine, boot
