# Slice 17/20 — Persistence, replay and failure QA

Host **Nox** (Glass execution MCP 429), 4 November 2026 NZDT; report 2026-11-04T22:52:58+13:00. Current checkout based on local `2d39c36` (one commit ahead of origin/main at slice start), clean before edits. Read AGENTS, roadmap, rules, Stage 8 and E2E audit.

## Changes

- `lib/main.dart`: Confirm before importing a valid replay over a saved match, with Keep saved match / Import and replace; clearly explain imported replay resumes hot-seat because shared event codes omit AI-seat settings. Invalid input never shows the replacement dialog.
- `lib/replay_codes.dart`: Apply the same 1 MiB decompressed-size bound to raw JSON imports, including multi-byte UTF-8; compact codes retain existing gzip bound.
- Regression tests: `test/persistence_replay_failures_test.dart` exercises cancel/confirm persistence, post-import session computerSeats, invalid input retaining saved AI state, corrupt session metadata falling back to legacy replay. `test/replay_codes_test.dart` covers oversized raw ASCII/UTF8.

## Buildq verification (real Nox runs)

| Job | Result |
| --- | --- |
| #4540 | Initial focused run: one test failed due offscreen Import replay hit target; amended test. |
| #4541 | Initial analyzer: async BuildContext lint; amended mounted guard. |
| #4542 | First Linux release built successfully. |
| #4543 | Initial Android release failed: checkout's hardcoded Glass JDK 17 path not present on Nox. |
| **#4544** | **PASS**, focused persistence/replay tests. |
| **#4545** | **PASS, 131 Flutter tests** (`flutter test test/ --reporter expanded`). |
| **#4546** | **PASS**, `flutter analyze lib test tool`, zero issues. |
| **#4547** | **PASS**, `flutter build linux --release`. |
| **#4548** | **PASS**, `flutter build apk --release` with Nox `JAVA_HOME=/usr/lib/jvm/java-21-openjdk` and GRADLE_OPTS override only; no project Java path edit. |

APK 54873874 bytes SHA256 `e17eae009dffeacc822adbdd5e658c7ac55bfb7c0a2a07267e387e7c53ff6e03`. Linux libapp.so SHA256 `b2b4438d6f274b9bb81e49af162e5174d17770f2c600539c4c38f1f73978dc6f`. Built only on Android; **APK not installed**.

## Genuine Linux E2E

[35-row screenshot manifest](SCREENSHOT-MANIFEST.md), 35 PNGs, all visually inspected; original black/clipped and transitional frames are retained honestly. Isolated Linux release, Xvfb `:177`, private XDG data/cache.

1. Started hot-seat; used real legal-target list to place Village vertex 0 and Road edge 0. Inspected the real shared_preferences.json: exactly two ordered events, saved session and raw replay both present.
2. Navigated Home; cleanly stopped release process; cold-relaunched and resumed at Player 2 privacy handoff, same 1 VP / Road 1 for Player 1; no duplicate events.
3. Clicked Copy replay (real snackbar), pasted via Ctrl+V into the actual Import replay dialog (showing both events). Load triggered **new replacement confirmation**; Keep returned Home with saved replay still exactly two events and identical SHA.
4. Imported a **real 89-event replay** from Slice 15 deterministic scenario code. Explicit Import and replace changed on-disk save to 89 events, names Bot-0/Bot-1/Bot-2, seed 1000. Compared saved 89 event objects and seed to decompressed original fixture: **exact equality**. UI displayed Bot-1 private handoff then Round 7 actions, 2/15 VP, strategy card 1/4.
5. Sent SIGKILL to the exact isolated Linux app PID (validated process command), cold-relaunched with same XDG session, continued from 89-event save. Screens #30 and #35 match board layout/score/hand, saved events remained 89. This is forced process failure, not proof of recovering from every possible engine crash.

Visual notes: Home/setup/privacy/replay-confirmation hierarchy, contrast and typography were good at 390×844, with a single primary action and understandable cancellation. Board action section remains dense under the map, as previous stages observed. Initial Linux GTK 1280px window clipped the 390px Xvfb; resized/reframed and captured followups; a few immediate frames were black/transitioning and explicitly marked.

## Unverified / remaining

- Glass unavailable with HTTP 429. Nox Waydroid already had `nz.presley.stoneandbanner/.MainActivity` foreground in Android user **11** (verified read-only). Did not switch user, disrupt the concurrent session, install or touch Android UI. Therefore **no Waydroid E2E**, device rotation/background/Android lifecycle or on-device corruption test claimed.
- Linux app did not undergo native mobile rotation, gesture backgrounding, loading-state manipulation or 15-point victory/rematch in this slice. Existing baseline tests cover victory/replay and coordinator lifecycle, but do not replace fresh slice-17 UI proof.
- Valid raw/compact error input was exercised in widget tests; not through this live Linux session. No Samsung, public release, hosted services, or LAN testing.
- The code maintains pure deterministic reducer and offline AI; no rule changes, new dependency or remote service.

Worktree just before evidence commit:

```
M lib/main.dart
 M lib/replay_codes.dart
 M test/replay_codes_test.dart
?? test/persistence_replay_failures_test.dart
```

## Final handoff

Committed validated source/docs locally as `2306601` on `main`, clean worktree afterward (not pushed by this slice). Isolated `stone17-*` Linux app/Xvfb service units stopped after the run; screenshots, manifest, run evidence and private test XDG save preserved. Ended 2026-11-04T22:55:13+13:00. No other user or Waydroid processes were stopped.
