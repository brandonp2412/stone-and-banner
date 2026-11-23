# Stone & Banner — Android visual playthrough (18 November 2026)

## Scope and outcome

- Devices: Glass Waydroid (Android 13, 432×960/960×432), and `stone_design_api35` (Android 15, 1280×640, density 240).
- Installed current Glass working-tree Android-x64 debug build on the Android 15 emulator; the earlier installed build was also viewed.
- Played a **complete 3-player match** (Player 1, Computer 1, Computer 2), from setup through two initial villages and roads, rolling, bank/player trading, build/upgrade, cards, developments, bandit theft, invasion, and final results.
- **Computer 2 won round 33 with 16/15 Renown**; Computer 1 ended at 8, Player 1 at 3. Verified the defeat modal, View board, Results, and Home navigation.
- Screenshot evidence was observed live via Glass Mobile MCP, with selected PNGs retained alongside this document.

## Findings, ordered by priority

1. **P1 — Turn timer can expire while the player is in a modal.** During an open player-trade offer the turn counted down and the app advanced to round 2. A player constructing an offer can lose their opportunity without having chosen to end their turn. Pause the turn timer for blocking dialogs, or provide explicit countdown and draft preservation/cancel rationale. Evidence: mobile visual inspection of modal and later turn transition; `10-standing-offer.png` shows the earlier old-design modal; full-screen actions and current trade view were also inspected.
2. **P1 — HUD/status copy overlaps the board.** The top-left round/fleet/status section occupies map space; e.g. “Shape your rea...” and “Computer 2 wi...” become ellipsised over tile graphics, and fleet/defence text collides with the title. Reserve an opaque HUD region or move phase information into a dedicated compact banner. Evidence: `round10-board.png`, `round33-postmatch-board.png`.
3. **P2 — Postmatch right-side button text is cramped.** The disabled “Match complete” button wraps over three lines on the post-match map, which looks broken and consumes vertical map space. Use a single compact status chip or remove that disabled CTA. Evidence: `round33-postmatch-board.png`.
4. **P2 — Overlay visual effects compete with score labels and board.** AI roll overlays, score panel, and production toast simultaneously occupy the upper/central map; observed at the round-20 village upgrade/AI transition. Stagger effects, keep resource toasts low, avoid text on tiles, constrain overlays to safe zones. `round18-board.png`, `round26-board.png` show typical board density; the overlap was observed in live screenshot.
5. **P2 — Home's bottom navigation is initially below the fold in landscape.** “Import replay” is partially off-screen and the offline-play caption is initially invisible at 1280×640; scrolling reveals them, so this is not an unreachable control but is a poor first-screen presentation. Evidence: `home-default-landscape.png` (initial).
6. **P2 — Visual target picker occupies most of screen.** In setup and bandit actions, “Choose legal board target” bottom sheet fills the majority of the display with large full-width rows; it obscures map context and may have a cut-off bottom row at 640px high. Consider a slimmer compact sheet/list with scroll indicator. Evidence: live screenshots during village/road placement and bandit selection.
7. **P3 — Realm page has excessive explanatory prose and scroll depth.** The three development tracks are far below an oversized explanatory card; first viewport gives little direct action. Put available tracks/costs first and move explanation into expandable help. Verified by scrolling the Realm tab.
8. **P3 — Strategic progression is unclear in the early game.** Cards says “Develop Town tracks to unlock card draws,” while the development tracks require a Town; the turn-to-turn path is hard to discover if no ore/brick resources are available. Contextual guidance and show-next-required-resource would help. Verified in actions Cards and Realm tabs.
9. **P3 — Some map labels are unusually small.** Port ratios such as “wood 2:1” and some per-junction annotations are difficult to read at landscape size. Increase text size or reveal in focused info overlay. Evidence: `round26-board.png`.

## Confirmed working

- New match setup (Vs AI, two AIs) and seed-generated start.
- Free village and road placement for all players, subsequent roll/phase navigation.
- Board target picker, roll, End turn, AI turns, bandit move and theft, invasion resolve.
- Trade UI navigation and disabled bank exchange when resources are insufficient (no false success observed).
- Selecting and buying a Town upgrade; Player 1 rose from 2 to 3 Renown and paid 2 wheat + 3 ore.
- Saved-match recovery after emulator crashes; end-of-match defeat persisted and was restored on relaunch.
- End-game defeat modal, View board, Results, Home.

## Environment issues — not attributed to Stone & Banner

- Glass Waydroid rendered widespread horizontal artefacts **even on the Android launcher**, with ANGLE/Venus graphics. Not evidence of a game rendering defect.
- `stone_design_api35` emulator crashed twice with native `qemu-system-x86_64` SIGSEGV; first after a long run near the finale, then again after reopening. A third restart using host GPU with Vulkan disabled successfully resumed saved game, exposing the already-completed result. These are emulator crashes, not confirmed game crashes.

## Evidence file index

- `home-default-landscape.png`: initial home view; bottom content off-screen.
- `10-standing-offer.png`: older trade dialog (pre-current debug build).
- `round10-board.png`: congested top-left HUD.
- `round18-board.png`, `round26-board.png`, `round31-pre-final.png`: progression and AI villages.
- `round33-defeat.png`: actual completed-match defeat modal.
- `round33-postmatch-board.png`: end-of-match board, overlaid status, miswrapped “Match complete” button.

**Limits:** This one run primarily used the simplest human strategy. It verifies AI-vs-human completion and the defeat flow, not a manually played human victory, LAN session, or every advanced strategy-card interaction. This report records the original observations; a follow-up implementation is documented below.


## Follow-up code changes — 18 November 2026

Changes applied directly to the existing Glass working tree, preserving its earlier uncommitted edits:

- `lib/ui/match_screen.dart`: local turn countdown pauses whenever a blocking route (dialog or target picker) covers the match. This prevents an offer from timing out while being composed. Added regression coverage.
- `lib/ui/match_screen.dart`: merged top-left phase and fleet text into a bounded opaque compact HUD with abbreviated landscape copy; retains full instructions in map accessibility semantics. Removes previously overlapping text.
- `lib/ui/match_screen.dart`: removed the disabled post-match turn button from the map, shortened compact setup buttons, enlarged port-ratio labels, and constrained target sheets with a larger accessible minimum at high text scales.
- `lib/ui/match_screen.dart`: moved activity cues from the scoreboard/board center into a narrow right-side slot; Realm development tracks now appear much higher with concise resource requirements and the disabled shortcut hidden.
- `lib/ui/match_activity.dart`: activity cues use compact landscape type/icon sizing, 2-line title limit, and no redundant second line for roll and end-turn events.
- `lib/main.dart`: landscape landing menu uses tighter spacing and keeps Import Replay visible without a clipped decorative footer.
- Tests updated for the new compact UI; current visual goldens refreshed. The `blocking dialog pauses the local turn clock` regression test was added in `test/turn_trade_ui_fixes_test.dart`.

**Verification:** `flutter analyze` on the modified UI files returned no issues; the complete `flutter test` suite passed **285/285**; `flutter build apk --debug --target-platform android-x64` succeeded. The APK was installed on the Glass Android 15 emulator and the game board, activity cues, home and Realm actions were visually inspected. New captures: `after-fixes-board-activity.png`, `after-fixes-realm.png`.

The emulator occasionally crashes with native graphics errors independently of the game. No changes were committed or pushed because this checkout already contains extensive unrelated uncommitted edits.
