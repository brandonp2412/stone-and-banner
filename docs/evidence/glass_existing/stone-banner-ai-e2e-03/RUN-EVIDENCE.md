# Slice 03 implementation/QA evidence — Glass

Recorded: 2026-11-04 18:34:33 NZDT. Source checkout: /home/brandon/stone-and-banner.

## Verification (all via buildq)

| Task | Exact command | Outcome |
| --- | --- | --- |
| #4741 | `flutter test test --reporter expanded` | PASS — 85 tests (includes 7 slice-03 tests) |
| #4742 | `flutter analyze lib test tool` | PASS — no issues |
| #4743 | `flutter pub run tool/ai_strategy_benchmark.dart 601 24 65` | PASS — seeded 24-match benchmark; see JSON |
| #4744 | `flutter build apk --release` | PASS — release APK built; no installation |

Flutter SDK: `/home/brandon/.local/share/flutter-stone-and-banner-3.47.6/bin/flutter` (Dart 3.13.5).
APK size: 54398538 bytes. SHA-256: `3f57b11e25d17e00780a2a1ceb8348a8f169831c603f38ee6d7340a43f4df372`.

## Measured 24 matches, seeds 601–624, cap 65 rounds

- Heuristic mean VP: **10.375**.
- Random opponent mean VP per seat: **2.5416666666666665**.
- Heuristic wins: **9** of **9** matches that actually finished; remaining **15** unfinished at round cap.
- Heuristic construction actions in action phase: **154** roads, **101** villages, **418** upgrades, **434** bank exchanges.
- This is performance against a seeded, whitelisted legal-random policy, **not** a human-strength or 24-game win-rate guarantee.

## UI and boundaries

- No UI actions/screenshot captures in this engine-only slice; see `SCREENSHOT-MANIFEST.md`.
- The strategy consumes the committed `AiActionAdapter` legal-action whitelist and dispatches via `applySelected` in tests/benchmark.
- No change to dice, rules, bank stock, replay reducer, UI, or network/server code.
- No device installation, physical-device check, visual QA, or LAN smoke is claimed.
