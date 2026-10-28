# Flutter UX contracts

Home → 3–4-seat local setup / Board / Rules. Seeded layouts and replay import/export are available. Privacy hand-off screens appear when the active seat or offer recipient changes. Use Material 3, large type, rounded surfaces, 48dp minimum touch targets, both icon and text for tracks, accessible semantics and reduced-motion respect. A single `CustomPainter` renders hex geometry; widgets dispatch legal engine actions and never decide costs. Reserve space for bottom actions, keep selection and reaction sheets stable, reveal private cards only to the intended seat. The Stage 2 board supports legal placement highlights, inspect, pan/zoom, seeded dice, Bandit choices, bank trades and consenting player trades.

## Stage 8 release UX

Home offers Resume saved match and replay import; either restores through a private seat handoff before showing hidden resources. Every accepted move autosaves the canonical private replay. Both compact sbz1: and JSON exports reveal other players' hidden hands, so share only with trusted participants.

Board's **Choose board target from list** shows the exact legal junction/road/Bandit choices as textual alternatives to hitting small board targets. Choosing a row still sends the usual engine event. Real TalkBack, keyboard, switch and large-font sessions are unverified; see STAGE8-EVIDENCE.md.
