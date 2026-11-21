# Completion 5/8 — Android UI, accessibility and layout QA

5 November 2026 NZDT. All screenshots are actual Android 15 emulator frames captured via `adb exec-out screencap -p` on Glass, visually inspected. Source baseline: `c395622` (the mobile action-panel source matches `7e77282`; the four-player branch changes only tests/docs). Isolated branch: `feature/android-accessibility-20261105`. No physical Samsung interaction, no shared Waydroid interaction, and no public release.

- Emulator: `remux_subtitles_pixel5_api35`, serial `emulator-5558`, Android API 35. Samsung-like 1080×2340 px / 440 dpi (~393×851 dp), narrow 720×1600 px / 360 dpi (320×711 dp), landscape 1600×720 px / 360 dpi (~711×320 dp).
- Font scale: 1.0 on baseline Home; 1.5 on most portrait gameplay; 1.6 on narrow and landscape. Widget layouts additionally checked at 320×640/1.6x, 390×844/2.0x and 800×360/1.5x.
- Baseline APK: completed cards/trades build `#5035`. Revised APK: `#5058`, SHA-256 `3c5485480dcda753a696a5ca2d660e23d5277218407b2a7692409dd1e65d53ee`, installed with `adb install -r`, then force-stopped/relaunched.
- Screenshot names carry action order and baseline/post-fix labels. `PASS` means controls and text were visibly usable without off-edge overlap; scrollable content may extend below the viewport. `LIMITED` marks a boundary rather than silently claiming it passed.

| Time NZDT | Screenshot | Action / expected | Observed verdict |
| --- | --- | --- | --- |
| 14:29:51 | [02_before_home_landscape.png](02_before_home_landscape.png) | Launch baseline in 1920×1080 landscape | **PASS:** Home CTA and nav accessible; wide cards centered |
| 14:30:27 | [03_before_home_samsung_like.png](03_before_home_samsung_like.png) | Switch to 1080×2340 portrait | **PASS:** Home, rules, LAN and replay entry readable |
| 14:30:46 | [04_before_setup_portrait.png](04_before_setup_portrait.png) | Open 3-player setup | **PASS:** Start button and player controls visible |
| 14:31:27 | [05_before_setup_large_text.png](05_before_setup_large_text.png) | Select Vs AI, four seats at 150% font | **PASS:** 1–3 AI options and Start remain accessible; player names scroll below |
| 14:31:50 | [06_before_handoff_large_text.png](06_before_handoff_large_text.png) | Start 1 human + 3 AI, board setup | **LIMITED:** Board is usable with target-list alternative; phase header exposed `setupVillage` |
| 14:33:24 | [07_before_board_large_text.png](07_before_board_large_text.png) | Place two Villages/Roads through legal semantic target sheets; AI completes remaining placements | **PASS:** Real match reached Roll phase; original header said `roll` |
| 14:33:51 | [08_before_actionpanel_large_text.png](08_before_actionpanel_large_text.png) | Roll dice, inspect action panel | **LIMITED:** End turn, Bank trade, Player trade usable; header leaked `actions` |
| 14:36:45 | [09_before_bank_320dp_160text.png](09_before_bank_320dp_160text.png) | Open Bank exchange at 320 dp / 160% text | **LIMITED:** Exchange disabled correctly, but reason was offscreen in scroll body |
| 14:37:43 | [10_before_playertrade_320dp.png](10_before_playertrade_320dp.png) | Open standing player offer | **PASS:** Target, escrow, quantities, request and CTA scroll correctly |
| 14:39:28 | [11_before_rules_320dp.png](11_before_rules_320dp.png) | Open Rules | **PASS:** Long rules scroll; no painted overflow |
| 14:40:56 | [12_before_glossary_320dp.png](12_before_glossary_320dp.png) | Expand Glossary | **PASS:** Expansion semantics exposed; content scrolls |
| 14:42:07 | [13_before_replay_dialog_320dp.png](13_before_replay_dialog_320dp.png) | Open replay-import dialog | **LIMITED:** Helper and unfocused label were ellipsized |
| 14:42:53 | [14_before_replay_keyboard_320dp.png](14_before_replay_keyboard_320dp.png) | Focus replay text field, show Gboard | **LIMITED:** Cancel/Load remain above keyboard, helper still ellipsized |
| 14:46:10 | [15_before_home_rotation_check_portrait.png](15_before_home_rotation_check_portrait.png) | First rotation attempt; physical dimensions still portrait | **LIMITED:** Recorded as portrait, not misrepresented as landscape |
| 14:46:46 | [16_before_home_actual_landscape_large_text.png](16_before_home_actual_landscape_large_text.png) | Rotate to real 1600×720 landscape | **PASS:** Home scrolls, nav accessible; very short vertical viewport |
| 14:47:13 | [17_before_board_landscape_large_text.png](17_before_board_landscape_large_text.png) | Open game in landscape | **PASS:** Game header and scroll region remain accessible; gameplay actions require scrolling |
| 14:48:51 | [18_after_home_resume_portrait.png](18_after_home_resume_portrait.png) | Install revised APK, force-stop and reopen | **PASS:** Saved match survives package replace/process restart; Continue visible |
| 14:49:13 | [19_after_board_phase_portrait.png](19_after_board_phase_portrait.png) | Continue persisted match | **PASS:** Same 2 VP human match, header now `Round 1 · Your turn` |
| 14:49:59 | [20_after_bank_320dp_160text.png](20_after_bank_320dp_160text.png) | Repeat narrow Bank exchange | **PASS:** `Insufficient goods to offer.` fixed directly above disabled Exchange |
| 14:53:08 | [21_after_replay_dialog_320dp.png](21_after_replay_dialog_320dp.png) | Repeat replay dialog | **PASS:** `Replay code` fully visible, two-line JSON/share-code helper readable |
| 14:53:36 | [22_after_replay_keyboard_320dp.png](22_after_replay_keyboard_320dp.png) | Focus revised dialog with Gboard | **PASS:** Label, helper, Cancel and Load all visible above keyboard |
| 14:55:52 | [23_after_board_scrolled_cards_320dp.png](23_after_board_scrolled_cards_320dp.png) | Scroll past board to Strategy hand, Town Developments, standings, replay export | **PASS** empty-hand panel and export controls; **LIMITED** card-detail not opened because this live state held zero cards |

## Accessibility and lifecycle

- Android accessibility node inspection exposed role/label for Home tabs, mode/AI selectors, the legal board-target chooser, every enumerated junction/road, trade selectors, disabled Exchange, replay actions, and collapsible Rules/Glossary. The board's CustomPainter itself does not expose each vertex; the explicit **Choose board target from list** sheet provides semantic equivalents and was used to complete setup.
- TalkBack package `com.google.android.marvin.talkback` was present. Its service was temporarily enabled on the isolated emulator and listed in `dumpsys accessibility`. A swipe did not yield a visually observable focus transition; spoken announcement quality was **not verified**. The service was disabled afterward. Do not count this as a complete TalkBack acceptance pass.
- Gboard text entry in the replay dialog was tested at 320 dp / 160%, before and after. Physical keyboard Tab/Escape behavior remains backed by focused Flutter widget tests, not a comprehensive real-hardware keyboard traversal audit.
- Orientation changed between portrait and landscape while the match persisted. Reinstall + process restart preserved Continue and the 2 VP turn. No proof of interrupted lifecycle during a live tactical response.
- The actual emulator did **not** exercise a card-detail sheet, a tactical reaction screen, or a 15-VP victory in this slice. Existing engine/widget regressions cover those paths, but that is not Android visual acceptance. These remain open for a dedicated Android fixture-driven pass.

## Verification and ownership

- `buildq #5048`: focused tests (including existing Stage 5 and accessibility) passed after initial test cleanup. `#5049`: scoped analyzer passed.
- `buildq #5055`: one test-helper failure from an offscreen Home item; corrected with scrolling. `#5056`: full `lib test tool` analyzer passed.
- `buildq #5057`: updated the board golden for the human-readable phase header; passed.
- `buildq #5058`: Android release build passed and the actual APK was installed on the isolated emulator.
- `buildq #5059`: final focused suite **19 tests passed**.
- `buildq #5060`: full-suite failure from one old test expecting the renamed replay label; assertion updated.
- `buildq #5061`: final full suite **150 tests passed**.
- `buildq #5062`: final analyzer `lib test tool` **no issues**.
- No changes to `main`, other slice worktrees, Nox, Pi, shared Glass Waydroid, physical Samsung, live services or public release. This branch is intentionally kept isolated for later owner-approved integration because other slice branches are concurrent and `main` has unrelated dirty edits.
