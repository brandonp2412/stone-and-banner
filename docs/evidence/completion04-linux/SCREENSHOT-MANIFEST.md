# Completion 4/8 — Glass Linux live screenshot/action manifest

5 November 2026 NZDT. Real Flutter Linux release on an isolated Xvfb `:79` display at 1280×720, operated with X11 mouse clicks. Source baseline `f36c843`; executable's `libapp.so` SHA-256 `4e987b156c19cfa139ba791e09c231010407035fc59da154d81aca18d6bff7f4`. The desktop and shared Waydroid were untouched. The app used dedicated `XDG_CONFIG_HOME`/`XDG_DATA_HOME` under `/home/brandon/.local/state/stone-and-banner/e2e/stone-banner-completion04-20261105/`.

All 16 frames were reviewed individually or as the [contact sheet](qa-contact-sheet.png), with selected frames opened at full resolution. No black frame, clipped primary button, or hidden-hand leak observed. First screenshot is before actions; subsequent screenshots follow the named click/restart.

| # | Screenshot (NZDT) | Input/action | Actual observed | Verdict |
| --- | --- | --- | --- | --- |
| 01 | [14:02:30](20261105T140230-01-home.png) | Launch isolated Linux release | Dark Home, New local match visible | PASS |
| 02 | [14:03:10](20261105T140310-02-setup.png) | Click New local match (640,195) | Setup: Hot-seat/3 seats default | PASS |
| 03 | [14:03:48](20261105T140348-03-vs-ai.png) | Click Vs AI (805,235) | AI opponent selection appears | PASS |
| 04 | [14:03:48](20261105T140348-04-four-players.png) | Click 4 players (796,284) | Four seats selected, 1–3 AI available | PASS |
| 05 | [14:04:29](20261105T140429-05-three-ai.png) | Click 3 AI (840,359) | 1 human / 3 computers selected | PASS |
| 06 | [14:04:30](20261105T140430-06-start-four-player-match.png) | Click Start match (636,431) | Real four-seat setup board, Player 1 | PASS |
| 07 | [14:05:06](20261105T140506-07-human-place-village.png) | Click legal junction (532,187) | Human Village, 1 VP, Road phase | PASS |
| 08 | [14:05:46](20261105T140546-08-human-place-road.png) | Click glowing side (502,204) | Private Computer turn overlay | PASS |
| 09 | [14:05:47](20261105T140547-09-three-ai-progress.png) | Observe without input | Automatic AI snake draft returned to Player 1 | PASS |
| 10 | [14:05:49](20261105T140549-10-three-ai-after-progress.png) | Observe settled result | Same board after AI completion, no repeated action | PASS |
| 11 | [14:07:25](20261105T140725-11-process-restart-home.png) | Stop this app service; relaunch executable with same save directory | Continue saved match appears | PASS |
| 12 | [14:08:17](20261105T140817-12-resume-four-player.png) | Click Continue (640,195) | Same Player 1 draft and AI pieces; no needless solo-human privacy gate | PASS |
| 13 | [14:08:59](20261105T140859-13-leave-board-to-home.png) | Click Home (213,669) | Home with Continue; local save retained | PASS |
| 14 | [14:08:59](20261105T140859-14-reenter-saved-board.png) | Click Board (640,669) | Exact four-seat board re-entered | PASS |
| 15 | [14:10:08](20261105T141008-15-human-second-village.png) | Click legal second junction (909,468) | Human at 2 VP, Road phase | PASS |
| 16 | [14:10:56](20261105T141056-16-human-second-road-round1.png) | Click glowing side (881,483) | All eight setup Village/Road pairs complete; Round 1 roll | PASS |

## Persistence checks

- After AI completed the snake draft, the on-disk session had `computerSeats: [1,2,3]`, 14 accepted events, replay SHA-256 `13d5c7d05f5b7596eb3f2089c4df13eda70ef7ca87d53db608e0446f0c61e3e9`.
- After stopping and relaunching the **actual Linux process**, opening Continue still reported exactly 14 events, the same AI seats and the **same** SHA-256.
- Leaving Home and re-entering did not change that saved hash.
- The human's subsequent second Village/Road increased the saved event count to 16; replay SHA-256 became `1056a5d8b631ba8a0ec382bfd7a25b7176940629d153ce952cd0e6c7c07274b7`.

## Explicit limitations

This is a real four-seat UI acceptance of automatic setup, private computer overlay, save/restart/resume and navigation, not a 15-VP victory or full-game autoplay. No real UI replay import/export, tactical private handoff between **multiple humans**, Invasion, Bandit or game-over was reached in this run. Four-seat replay round-trip and 1–3 AI private handoff/lifecycle scenarios are separately exercised by focused widget tests; do not conflate those with live UI proof. No Waydroid, Samsung, LAN, or public release was used.

An initial **separate** headless Cage keyboard attempt (not counted in the sixteen X11 PASS frames) had ambiguous focus and accidentally entered a default three-seat hot-seat match. It did demonstrate real saved data loading and private Player 1 handoff after restart, but that is not a four-seat acceptance. That compositor was stopped without touching the shared user session.
