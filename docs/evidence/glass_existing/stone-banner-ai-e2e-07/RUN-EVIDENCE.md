# Slice 07 — Human-vs-AI UX run evidence

4 November 2026 NZDT. Checkout: `/home/brandon/stone-and-banner` on Glass; current main base included concurrent Slice 06 coordinator commit `a5f23cb`. Existing uncommitted files were preserved until that commit landed.

## Delivered UX

- Prominent Material 3 **Hot-seat / Vs AI** mode selector in the local match card; the separate LAN room entry stays available.
- 3 seats allow 1–2 local AI; 4 seats allow 1–3. At least one human remains. Human controllers are editable under **Player names**; computer seats have deterministic labels.
- One local heuristic strategy only. No unsupported Easy/Medium/Hard claim.
- Start action is above collapsed optional player names/world seed, resolving the initial below-viewport button encountered at 390×844.
- One-human vs AI transitions directly to the board after computer moves; multi-human hot-seat sessions retain private handoff. AI coordinator continues to validate through the pure reducer, with saved seat ownership and replay.

## Exact verification

| Check | Glass buildq result |
| --- | --- |
| Slice 07 widget regressions (`flutter test test/ai_setup_widget_test.dart`) | **#4829 passed, 3 tests** |
| Full `flutter test test/ --reporter expanded` | **#4837 passed, 119 tests** |
| `flutter analyze lib test tool` after fixing one test-only curly-brace lint | **#4843 passed, no issues** |
| `flutter build apk --release` | **#4830 passed, 54.7 MB**; installed on Glass Waydroid |
| Direct `flutter build linux --release` in original checkout | **#4823 failed**: no Linux desktop scaffold in repository |
| Isolated temporary scaffold + `flutter build linux --release` | **#4842 passed**: `/tmp/stone-banner-ai07-linux-runner-20261104/build/linux/x64/release/bundle/stone_and_banner` |

Glass Flutter SDK: `/home/brandon/.local/share/flutter-stone-and-banner-3.47.6/bin/flutter` (Flutter 3.47.6, Dart 3.13.5). Build/test commands were enqueued with `buildq --label … --`. No external AI/backend, Riverpod, go_router, or public release was added.

## Actual app UI evidence

See [per-action screenshot manifest](SCREENSHOT-MANIFEST.md) with **28 images**. Linux release ran in a separate headless `cage` Wayland compositor; `grim` captured actual compositor output after each keyboard action. Early first frames were black before rendering and were recaptured once the app painted. Linux visually showed Home → Vs AI setup → Player 1 private handoff. Screenshot review found a clear primary action and no overflow in stable frames.

On Glass Waydroid the installed release app displayed Hot-seat and Vs AI setup in landscape and portrait (432×960), selected 4 seats and exposed 3 AI as an option. The device was **being controlled by a concurrent session**, which independently started gameplay and invalidated our next target ref; no independently attributable 3-AI tap claim, keyboard entry, full human-AI turn, or match finish on Waydroid. Nox Waydroid was occupied by a different app, so it was left untouched. Samsung was not used.

## Remaining gaps

1. Independently retest Waydroid 1-, 2- and 3-AI seat choices, text editing with IME, and an entire human-AI setup/turn after the shared device is free; capture each action.
2. Confirm focus-ring visibility and keyboard name entry on Linux (actual mode selection and navigation were observed, but text input was not).
3. The repository itself intentionally remains Android-targeted; the Linux QA runner was temporary and not added to main.
4. Physical accessibility, production signing, legal/IP and security/publication gates from Stage 8 remain open. No unsupported completion claim.


## Final visual refinement and rerun

The saved-match action wrapped onto two lines at 432×960. It was changed to single-line **Start new match**, with a separate **Replaces your saved match** caption. Updated isolated Linux screenshot 28 visually confirms the correction; the corrected APK was built but intentionally not reinstalled on the shared Waydroid session. buildq **#4848: 120 tests passed**, **#4849: analyze no issues**, **#4850: Android release APK built**, **#4851: isolated Linux release built**. Waydroid display size was restored to original 1792×1008.
