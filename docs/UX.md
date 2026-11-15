# Flutter UX contracts

Home → 3–4-seat local setup / Board / Rules. Seeded layouts and replay import/export are available. Privacy hand-off screens appear when the active seat or offer recipient changes. Use Material 3, large type, rounded surfaces, 48dp minimum touch targets, both icon and text for tracks, accessible semantics and reduced-motion respect. A single `CustomPainter` renders hex geometry; widgets dispatch legal engine actions and never decide costs. Reserve space for bottom actions, keep selection and reaction sheets stable, reveal private cards only to the intended seat. The Stage 2 board supports legal placement highlights, inspect, pan/zoom, seeded dice, Bandit choices, bank trades and consenting player trades.

## Stage 8 release UX

Home offers Resume saved match and replay import; either restores through a private seat handoff before showing hidden resources. Every accepted move autosaves the canonical private replay. Both compact sbz1: and JSON exports reveal other players' hidden hands, so share only with trusted participants.

Board's **Choose board target from list** shows the exact legal junction/road/Bandit choices as textual alternatives to hitting small board targets. Choosing a row still sends the usual engine event. Real TalkBack, keyboard, switch and large-font sessions are unverified; see STAGE8-EVIDENCE.md.

## Landscape tabletop redesign — November 2026

Mobile launches in either landscape direction with immersive system bars. The
Android activity also declares sensor landscape. The match occupies one table:
public player standings above the map, private goods along the bottom, and a
fixed action rail on the right. Build, Trade, Cards and Realm switch that rail
without moving or replacing the map. Roll, End turn and Resolve Invasion share
a fixed primary action position. A compact menu opens Home or Rules.

Setup uses two columns with a persistent Start action. Player names and the
world seed remain optional expanded settings. Home uses the existing original
crest alongside Continue/New match. Bank/player trades and strategy decisions
use dismissible dialogs over the table. Long choices scroll inside their panel;
the map and turn action stay in place. Large text can scroll player summaries
horizontally, with full names and scores supplied to semantics.

The map uses an original drawn terrain style and a shared tabletop projection
for painting, pointer targets and text target selection. Number tokens include
probability pips. The last dice total remains visible, with matching productive
hexes outlined. Pan/zoom has a reset control; the legal target list works even
when zoomed. Terrain decorations do not consume the saved random stream.

Private handoffs conceal the table until the intended seat confirms. A visiting
tactical responder sees the public map and their own choices, with the acting
player's inventory and cards concealed. Computer turns show public moves with
hands concealed and input disabled. Opening the match menu pauses computer
work; dismissing it resumes, while leaving the board keeps work paused.

Automated size coverage includes 640×320 and 844×390 phones and 1024×768,
with text scaling through 2×. These checks do not replace real TalkBack or
physical device QA. Release emulator evidence is in LANDSCAPE-REDESIGN.md.

On short phone displays, the player bar, inventory and action rail use a compact
layout. Road, Village and Upgrade share one row; their costs are available in
tooltips and the map instruction when selected. Both trade entry points remain
visible without scrolling. Cards become actionable after the roll and pending
events. Replay input scrolls above the landscape keyboard and disables
suggestions and autocorrect so a share code is preserved exactly.
