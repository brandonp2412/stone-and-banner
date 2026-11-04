# Slice 19 — visual consistency screenshot manifest

Date: 4 November 2026 NZDT. Host: Nox fallback (Glass connector HTTP 429). Independent Linux release on Xvfb :119 with XDG-isolated state, 440x940.

| # | Action | Expected | Actual / visual inspection | Verdict | Tweak decision | Screenshot |
|---:|---|---|---|---|---|---|
| 001 | Launch initial isolated Linux app under :119 | Home renders | 188-byte blank Xvfb capture; window not visible | FAIL | Set GDK_BACKEND=x11; retest #002 | [001_linux_home_before.png](001_linux_home_before.png) |
| 002 | Open X11 backend and reframe Linux Home | Readable Home | Home renders 440x940 with clear one-CTA hierarchy, navigation and art; no clipping | PASS | No change | [002_linux_home_x11_before.png](002_linux_home_x11_before.png) |
| 003 | Tap Import replay before focus | Replay dialog opens | Home unchanged because isolated GTK window lacked input focus | LIMITED | Focus window and retry #005 | [003_linux_import_dialog_before.png](003_linux_import_dialog_before.png) |
| 004 | Focus isolated Linux app window | App receives input | Home unchanged and legible; focus state not visually apparent | LIMITED | Retry Import; app responds #005 | [004_linux_focus_home_before.png](004_linux_focus_home_before.png) |
| 005 | Tap Import replay after focus | Replay dialog opens | Centered dialog, readable input and actions; balanced spacing | PASS | No change | [005_linux_import_dialog_open_before.png](005_linux_import_dialog_open_before.png) |
| 006 | Type authentic 953-character replay code | Code appears and Load remains reachable | Outlined field scrolls long code; Load unobstructed; no overflow | PASS | No change | [006_linux_replay_typed_before.png](006_linux_replay_typed_before.png) |
| 007 | Load 89-event replay | Private handoff shown | Bot-1 privacy handoff visible, single clear ready button | PASS | No change | [007_linux_replay_loaded_before.png](007_linux_replay_loaded_before.png) |
| 008 | Reveal Bot-1 match board | Board in action phase | 19-hex board and resources legible; mostly disabled chips crowd screen | PASS / VISUAL ISSUE | Proposed hide unavailable chips and collapse developments; not implemented | [008_linux_replay_revealed_before.png](008_linux_replay_revealed_before.png) |
| 009 | Scroll six notches to action panel | Actions, cards, developments and trade visible | Nine action chips include seven disabled; three disabled Develop controls; trading pushed down | PASS / VISUAL ISSUE | Highest-priority refinement identified, not implemented | [009_linux_actions_scrolled_before.png](009_linux_actions_scrolled_before.png) |

## Cross-flow comparison

The [historical contact sheet](contact_sheet_prior_flows_01.jpg) compares nine earlier real captures: Nox Waydroid board, Linux and Waydroid setup, Linux and Waydroid action states, card sheet, LAN setup, replay replacement and Home. Historical captures are not fresh retests. This slice did not complete an exhaustive cross-platform sheet covering Rules, errors, reactions, trade and game-over.

## Factual handoff

- Worktree baseline: main at a7531b7, initially clean and ahead of origin/main by one commit.
- Live Linux: existing release imported an authentic 89-event replay through UI, reaching Bot-1 Round 7 actions.
- Proposed fix: filter unavailable action chips; collapse Town Developments using ExpansionTile while retaining develop controls, and adapt the existing widget test.
- No source changes or after-state screenshot. The code-editing connector stalled and aborted. No Flutter tests, analyzer or new release build were run.
- No Waydroid screen opened or acted on. Shared sessions left untouched; no Samsung or public release.
- This isolated Linux session was stopped during handoff.
