# Cozy Parchment prototype — verdict pending

Throwaway design spike. Delete it after the winning ideas are absorbed into
`overlay.html`.

## Question

How much of the handoff's warm parchment language can the real 560×320 native
overlay carry without losing the quiet Midnight Familiar base?

## Run

```bash
python3 -m http.server 5199 --directory .
```

Open <http://127.0.0.1:5199/mac/cozy-parchment-prototype.html>.

- `?variant=A` — Pocket journal: parchment only on the summoned journal.
- `?variant=B` — Pinned field note: shallower note, mascot overlaps it, ambient
  chips step back.
- `?variant=C` — Open folio: index rail plus content page; strongest hierarchy.

The bottom switcher also exercises mascot, focus state, and three contrasting
desktop backgrounds. All fixture data is in memory.

## First visual pass

- A is the safest production direction and preserves the ambient-product feel.
- B has the most personality and makes the mascot/page relationship feel alive.
- C makes the journal easiest to scan, but uses nearly the full overlay canvas.

## Verdict

TBD after hands-on comparison. Likely outcome: A as the production shell, with
one structural idea borrowed from B or C.
