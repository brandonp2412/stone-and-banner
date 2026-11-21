# Stone & Banner completion 4/8 — four-player AI and save/resume

5 November 2026 NZDT · Glass · isolated branch `feature/fourplayer-resume-e2e-20261105` based on `origin/main` `f36c843`.

## Delivered and observed

- **Real Linux GUI (Xvfb :79, 1280×720):** Home → Vs AI → four players → three AI → human's first Village/Road → automatic three-AI snake draft (forward and reverse) → return to human for second Village/Road → Round 1 roll. All 16 timestamped screenshots and per-action observations are in [the manifest](evidence/completion04-linux/SCREENSHOT-MANIFEST.md), plus a [contact sheet](evidence/completion04-linux/qa-contact-sheet.png).
- **Process restart:** stopped and restarted this isolated Linux app, retaining only the dedicated XDG save path. Home showed Continue saved match, and the same four-seat game resumed with the same three AI seats, 14 accepted events and identical replay SHA-256. Leaving to Home and re-entering likewise preserved it. Completing the human's next Village/Road moved the saved event count to 16 without reset.
- **Tests:** new `test/four_player_ai_resume_widget_test.dart` covers one human/three AIs through both snake-draft directions, replay compact-code round-trip, private multi-human handoff for one/two AIs, saved AI assignments across widget restart, and pausing/resuming an in-flight AI turn through the Flutter lifecycle without duplicate events.
- The offline deterministic engine, Material 3 UI, AI reducer legality and existing autosave are unchanged. No proprietary services or new dependencies.

## Glass buildq verification

| ID | Command | Result |
| --- | --- | --- |
| `#5010` | Flutter 3.47.6 `build linux --release` | PASS; screenshot-tested Linux release, `libapp.so` SHA-256 `4e987b156c19cfa139ba791e09c231010407035fc59da154d81aca18d6bff7f4` |
| `#5012` | `flutter test test/four_player_ai_resume_widget_test.dart` | PASS 3/3 initial tests |
| `#5013` | `flutter analyze lib test tool` | PASS, no issues |
| `#5014` | `flutter test test/` | PASS 140/140 initial suite |
| `#5015` | `flutter build apk --release` | PASS; built only, **not installed** |
| `#5031` | Focused widget rerun after lifecycle case | PASS 4/4 |
| `#5036` | Final `flutter test test/` | PASS **141/141** |
| `#5037` | Final `flutter analyze lib test tool` | PASS, no issues |

Android release APK was not installed, and the shared Waydroid, Samsung, Nox runtime and any other slice's app were not touched.

## Boundaries and handoff

- This is **not** a naturally finished four-player 15-VP match. Live Invasion, reactions, Bandit, late-game victory and game-over were not reached here. An imported 15-VP victory in earlier evidence is not a substitute for a natural game.
- Actual Linux UI replay **copy/import** was not traversed; compact replay equivalence was validated in the widget test and existing engine tests. No physical-device acceptance or live Android screenshot is claimed.
- An isolated initial Cage keyboard-only route had ambiguous focus and was abandoned for precise X11 mouse control. Its three-seat hot-seat match and private restart screen are not counted as four-player proof.
- The primary Glass `/home/brandon/stone-and-banner` checkout was left dirty exactly as found; mobile-actions (1/8), natural-match (2/8), cards/trades (3/8) and Nox reconciliation worktrees were not edited. Keep this isolated feature branch until active owners reconcile; integrate with the latest main only after those owners' validated changes are coordinated. No public release.
