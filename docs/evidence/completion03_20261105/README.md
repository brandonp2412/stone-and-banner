# Completion 3/8 — live cards and tactical E2E (5 Nov 2026 NZDT)

Source branch: `feature/cards-trades-e2e-20261105`, based on 1/8 mobile UI commit `7e7728201b076a7ba064f4b6e9fbdd64577b5f67` (which includes reconciliation `f35dd33`). Neither the main checkout's dirty files nor 1/8, 2/8, and reconciliation worktrees were edited.

## Real GUI configuration

- Glass Linux release build via buildq **#5009**, source SHA above, executable SHA-256 `85054175c8e4d6ee0b66294903f210bd8d1ce2131e3a56ef16dc2ad2a7000c24`.
- Isolated hidden Cage/headless Wayland compositor, **392×844 px** (390px caused a pixman/stride capture error). Independent `XDG_CONFIG_HOME` and `XDG_DATA_HOME` to protect normal saved matches. No shared Waydroid, Samsung, LAN, or public release touched.
- Every meaningful action produced a timestamped screenshot in `/home/brandon/.local/state/stone-and-banner/e2e/stone-banner-completion-03-20261105/linux-isolated/`; the corrected harness session records platform/build/source. The earlier incorrectly scoped 3840×1080 blank captures are retained in `linux-glass/` as failures. This folder curates *selected visually inspected* before/after screenshots, not a claim that every exploratory frame passed review.
- Tiny wlroots virtual-pointer helper `tool/e2e_wayland_pointer.c` compiled with `gcc -O2 tool/e2e_wayland_pointer.c -lwayland-client -lm`. Its output-specific pointer binding and delayed press made safe interactions in the isolated compositor possible; it must not target a shared or visible desktop.

## Observed fixture-driven flows (not natural match play)

| Flow | Before | GUI action and observed after | Replay proof |
| --- | --- | --- | --- |
| Strategy card | [Board](card-before-board.png), [Founding Charter choice](card-choice-sheet.png) | Bot-1 selected *Collect listed supplies* and played the held Governance card; [after](card-after-play.png) shows hand **1/4→0/4**, brick **0→1**, coin **1→2**, event **89→90** | `test/fixtures/completion3_card_pre.json` and `completion3_card_after_live_gui.json`; last event `cardPlay`; pure reducer snapshot equals live UI replay |
| Bandit relocation | [Bandit phase](bandit-before.png), [legal target chooser](bandit-targets.png) | Bot-2 chose legal Hex 3; [after](bandit-after-move.png) shows the Bandit moved and actions resumed. No Knight response happened in *this* relocation. | Seed 1000, replay checkpoint event count 18; event 19 was observed in GUI, but no exported post-event replay fixture for this particular movement |
| Invasion aid and resolution | [Bot-2 response](invasion-aid-before.png) | Pledged one wheat, [private handback](invasion-aid-after.png); Bot-0 [saw emergency aid +1 and Resolve Invasion](invasion-resolve-before.png), clicked Resolve, [returned to roll](invasion-after.png) with an explicit failed-defence outcome | Accepted seed-46 tactical-Invasion checkpoint at event 22; result screens visually observed; exported post-Invasion replay was not retained |
| Knight interception | [Bot-0 private response](knight-intercept-before.png) | Clicked *Intercept with Knight*, [private handback](knight-intercept-after.png), [Bot-1 resumed actions](knight-handback.png) without a tactical dead end | `test/fixtures/completion3_knight_pre.json` and `completion3_knight_after_live_gui.json`; seed 15, event **47→48**, final `tactical` choice `intercept`, legal reducer snapshot replay verified |

**Limitations:** Bank exchange and standing-offer posting/accept/counter/withdrawal/expiry were not successfully completed through this GUI slice. Governance countercards, out-of-turn Pass/timeout, card draws at a roll, and a natural 15-VP game were not observed here. Existing engine/widget tests cover parts of those mechanics but are not substitutes for live UI acceptance. No claim of complete 3/8 acceptance is made.

## Targeted regressions and jobs

`test/completion3_card_gui_replay_test.dart` checks exact replay continuation for card play and Knight interception, card resource transfer/exhaustion and a 392px card-bottom-sheet action. The source JSON fixtures derive from real running GUI events, and the pre-event checkpoints are accepted seed replays, never handcrafted resource-injected save states.

- buildq **#5024**: first two focused tests passed, **#5025**: analyzer clean.
- buildq **#5032**: 3 targeted tests passed (card replay, Knight interception, 392px card sheet); **#5033**: analyzer `lib test tool` clean; **#5034**: **145 full Flutter tests passed**; **#5035**: release APK built, 54,955,834 bytes, SHA-256 `dd5967a7d47a814a0a9c29baea7eb1144a86026b4a84a14e48e5600a81d4d9fb`. Build only: APK was not installed or smoked on Android in this slice.
