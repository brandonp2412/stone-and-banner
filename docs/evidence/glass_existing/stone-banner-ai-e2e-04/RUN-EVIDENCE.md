# Stone & Banner — AI slice 04/20 run evidence

Recorded: 2026-11-04 18:57:38 NZDT. Host: Glass, `/home/brandon/stone-and-banner`. Baseline main: `4491023` (slice 03 committed). Slice 04 validated commit: `565804509f148492067dfb6f94ed9421963dd72c` on local main. `docs/E2E-AUDIT.md` indexes this evidence.

## Implemented

- Extended `AiTurnView` with an immutable `AiStrategySignals` DTO containing public seasons/rounds, Town/Capital source-terrain production pips, own development levels and Knights, public Knight positions, Reaver/Invasion parameters, own dry-roll/relief and score deficit, finite bank stock, and legal trading rate. No opponent resource stores, cards, deck order or future rolls are exposed.
- Added `AiActionAdapter.advancedDecision` to prioritize VP, productive Town Development, Commerce II, Governance defence and Aqueduct drought recovery, plus threat-driven Knight activation/promotion/recruitment, Town fortification and Knight displacement. Invasion aid spends only a legal wheat/ore amount when the public gap may be bridged; otherwise passes. Bank trades use legal stock-backed candidates, only for deficits while preserving the next build cost.
- Integrated the planner into `HeuristicAi` for tactical responses and action phase, retaining its earlier setup/site/road/card heuristics. Enforced eight post-roll events per turn; no reducer rules or network/backend changed.
- Twelve new deterministic tests in `test/ai_advanced_strategy_test.dart`: production/season signals, Town development, Capital resource targeting, Knight activation/promotion, fortification, displacement, invasion aid/pass (including wheat-only impossible gap), catch-up 3:1 and exhausted bank, Aqueduct drought planning, action cap/finished state, hidden-hand invariance, and multi-round replay with bank + escrow conservation.

## Verification — exact Glass commands (scheduled with buildq)

| Job | Command | Observed result |
| --- | --- | --- |
| #4770 | `flutter test test/ --reporter expanded` | Passed, 97 tests, 0 failures |
| #4771 | `flutter analyze lib test tool` | Passed, zero issues |
| #4772 | `flutter build apk --release` | Passed, APK 54.4 MB; build only, not installed |
| #4773 | `dart run tool/ai_strategy_benchmark.dart 801 24 50` | 24 seeded games; heuristic 7.6667 mean VP, random-rival 2.6042 mean VP/seat; 3 finished games, all 3 won by heuristic; 11,135 event steps |

Flutter: `/home/brandon/.local/share/flutter-stone-and-banner-3.47.6/bin/flutter` (3.47.6 / Dart 3.13.5). Release APK: `/home/brandon/stone-and-banner/build/app/outputs/flutter-apk/app-release.apk`; bytes: `54398538`; SHA-256: `3f57b11e25d17e00780a2a1ceb8348a8f169831c603f38ee6d7340a43f4df372`. SDK warned about Android SDK XML version 4 vs parser version 3 during release, but Gradle finished successfully. There was no install or device launch.

### Diagnostics and correction

- Initial analyzer #4746 found three brace-style hints, all fixed before successful full analysis.
- Initial focused test #4745 stalled in observation setup; diagnostic retries #4747/#4749/#4750/#4751 were stopped, traced to the score-aggregation expression and replaced with an explicit bounded loop. Diagnostic #4752 passed its targeted test; clean suite #4753 passed nine scenarios. No assertion is made about a Dart runtime root cause.
- Post-QA refinements prevented wheat-only aid when the public Invasion gap cannot be bridged and prioritize Capital material trades after the first Town; final #4770–#4772 reran after both changes.
- `git diff --check` passed before final verification.

## UI evidence and boundaries

[SCREENSHOT-MANIFEST.md](SCREENSHOT-MANIFEST.md) records **zero UI screens, zero UI actions, zero screenshots**. No Linux/Waydroid application screen was opened, so there is no claim of visual inspection, UI behavior, end-to-end human-vs-AI gameplay, accessible controls, live Invasion screen or frame quality.

Automated scenarios operate on reducer-authorized immutable states. Artificial resource fixtures balance the finite bank; hidden-hand mutation and bounded action-count fixtures are intentionally synthetic and do not purport to be replayable from their pre-fixture history. The separate multi-round tests assert replay snapshot identity after every applied legal event and byte-identical seeded exports.

The benchmark contrasts only one deterministic heuristic with legal-random rivals for 24 seeds; many games hit the round cap. It is **not** a win-rate estimate against skilled humans or a season balance proof. The live Match UI still needs local AI seat selection and an automated turn controller in later slices, followed by per-interaction Linux/Waydroid screenshots and visual QA. Signing, IP, privacy/security, accessibility and physical-device gates remain outstanding. No Samsung test or public deployment.
