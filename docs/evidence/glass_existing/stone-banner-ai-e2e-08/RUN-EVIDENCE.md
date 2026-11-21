# Stone & Banner Slice 08 — AI match stability and fairness

4 November 2026 (NZDT), Glass (`/home/brandon/stone-and-banner`), starting `main` `2729d1f`; scoped slice committed as `891c3a5` on `main` (not pushed). Offline pure Dart and Flutter SDK 3.47.6 / Dart 3.13.5. No external AI, public service, Samsung or deployment.

## Corpus and invariants

New reusable `tool/ai_stability_corpus.dart` uses the scoped AI adapter and deterministic `HeuristicAi` for all seats, or rotates **one scripted legal-random input seat** (called simulated human, not a real human). Every action is validated by `AiActionAdapter.applySelected` and `MatchEngine.apply`; the seeded board uses `7 * seed + 11`. During every accepted event, it checks bank + hands + escrow = 19 for each resource, all nonnegative inventories, conserved physical Strategy Card counts across draw/discard/hands, correct event ordinal, score/15-VP phase consistency, and road-holder validity on road-relevant events. At the end of each match it checks full exported/imported and direct reducer replay snapshot equality. It stops after 90 rounds or an event-count limit, checks the 45-second wall-clock threshold after each accepted event (not a preemptive guard for a hung synchronous call), and captures decision and reducer timings. The cap is censoring, **not** a loss or a fabricated victory.

- `buildq #4795`: seeds **7200–7279**, 80 per cohort × (3/4 seats) × (all-AI/scripted input) = **320 matches**; 0 failures; 69.018 seconds.
- `buildq #4805`: independent seeds **7600–7799**, 200 per cohort = **800 matches**; 0 failures; 166.613 seconds.
- **Total: 1,120 matches, 1,023,024 accepted events, 0 legality, conservation, score, replay, event-cap or per-match wall-clock failures.** 51 matches did not finish by round 90; see [exact seeds and final states](CAPPED-MATCHES.md). These are open noncompletion cases, not loop violations.

Aggregate sampled events included 21,602 Strategy Card plays; 50,681 tactical responses; 25,271 invasion resolutions; 26,403 roads; 16,414 villages; 23,860 upgrades; 19,565 developments; 169,286 standing-trade proposals; and 127,418 trade responses. Tactical windows were overwhelmingly Invasion; a handful of Governance responses occurred. **No Bandit interception windows were exercised** because the privacy-scoped AI deliberately avoids victim-dependent theft actions. That mechanic is not corpus-validated here. The event counts are recorded per run in `summary.json` and per match in `records.jsonl`.

| Seats | Input policies | Games completed by 90 rounds | Wins by opening seat (0, 1, ...) | First-seat share of completed | Equal-seat reference |
| --- | --- | ---: | --- | ---: | ---: |
| 3 | All heuristic AI | 266/280 | 100, 92, 74 | 37.6% | 33.3% |
| 3 | 2 AI + one scripted legal-random seat | 244/280 | 91, 79, 74 | 37.3% | 33.3% |
| 4 | All heuristic AI | 280/280 | 88, 58, 60, 74 | 31.4% | 25.0% |
| 4 | 3 AI + one scripted legal-random seat | 279/280 | 85, 61, 65, 68 | 30.5% | 25.0% |

Four-seat first-seat advantage is an **observed bot-model balance risk**, not proof of a rules defect or real-human unfairness. For all-AI four-seat games, first-seat 88/280 has a Wilson 95% interval approximately **26.3–37.1%** (equal baseline 25%; one-sided binomial tail ≈ 0.009 without multiplicity adjustment). Three-seat all-AI first-seat 100/266 is less decisive (one-sided tail ≈ 0.080). Rules and bot tactics were **not tuned**; player skill, seat-policy interactions, draft position and independent policy families remain unisolated. Scripted legal-random input won 0 of 523 completed mixed-policy matches, which confirms it is a weak *input simulator*, not a human benchmark.

The main corpus had decision p99 ≤ **0.636 ms**, maximum **11.513 ms** across the two ranges; slowest whole match **563 ms**; no observed 45-second freeze. Wall timings are Glass Dart harness measurements, not Flutter UI frame pacing. Even completed matches with many actions can still be slow in UI, which was not tested here.

## Independent same-seed equality

After adding an ordered-event FNV-1a audit fingerprint, `buildq #4811` and `#4812` each ran seeds **8100–8123** in the same four cohorts (96 matches per run). **All 96 paired event fingerprints, winners and score arrays matched exactly** despite different wall timings. Both runs reported 0 errors. FNV is only a reproducibility checksum; each match also passed full snapshot replay equality. Results are in `repeat-a/` and `repeat-b/`.

## Focused tie/victory tests and Flutter checks

- `test/ai_match_stability_test.dart` creates topology fixtures for equal five-edge longest roads: incumbent keeps +2 VP; a fresh tie gets no holder; a sixth road transfers the honour and +2 VP. It also checks a synthetic score fixture at 14 vs 15 VP. `buildq #4800`: **2/2 passed**. Fixtures are not counted as end-to-end self-play victories.
- `buildq #4806`: **115 non-golden Flutter tests passed** (explicitly excluded `test/visual_test.dart`).
- `buildq #4813`: `flutter analyze lib test tool` **passed, zero issues**. Initial `#4801` reported six lint infos in the new tool; they were corrected before `#4802` and final `#4813` passed.
- `buildq #4804`: `flutter build apk --release` **passed** (55.0 MB reported), built only, **not installed or interacted with**. No claim of APK release readiness.
- Full test attempt `buildq #4803`: **115 passed, 1 failed**, specifically existing Home golden in `test/visual_test.dart`. The already-dirty, concurrently edited `lib/main.dart` adds the computer-play toggle and changes the 390×844 Home layout. Test screenshots were preserved in `golden-failure/` and visually inspected: "Start match" is pushed under bottom navigation. No golden was updated and no concurrent UI work was changed. See [screenshot/action manifest](SCREENSHOT-MANIFEST.md).
- `buildq #4814` **subsequently passed all 116 Flutter tests** after the overlapping UI work updated `test/goldens/home.png`. That is a green test result, **not a visual acceptance**: the updated golden itself was visually inspected and still shows the start button cut off behind the fixed bottom navigation at 390×844. Slice 08 did not update either the UI or that golden.

## Reproduction and exact boundaries

Run from `/home/brandon/stone-and-banner` with `/home/brandon/.local/share/flutter-stone-and-banner-3.47.6/bin/dart`:

```sh
buildq --wait -- dart run tool/ai_stability_corpus.dart 7200 80 90 /home/brandon/.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-08/corpus
buildq --wait -- dart run tool/ai_stability_corpus.dart 7600 200 90 /home/brandon/.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-08/confirmation
buildq --wait -- flutter test test/ai_match_stability_test.dart
buildq --wait -- flutter analyze lib test tool
```

Use the explicit SDK paths above if default `dart/flutter` picks Dart 3.13.4 and fails the `^3.13.5` constraint. Each corpus directory contains `summary.json`, `records.jsonl` (seed, board seed, seat count, simulated-human seat, round/steps, result and event-type counts), and `failures.jsonl` (empty here; on failure contains seed, current action/phase, stack and event-prefix reproduction). `repeat-a/` and `repeat-b/` additionally contain `eventHash64` per match. `CAPPED-MATCHES.md` enumerates all 51 nonfinished runs.

**Unresolved:** The production reducer rejects **two seats** (`Choose 3 or 4 players`), so no honest two-seat corpus can be claimed without a separately designed/tested rule change. Zero physical humans participated. No end-to-end AI Flutter/Waydroid screen was opened: actual UI screen/actions/screenshots **none**, as recorded in the manifest. Governance/Bandit interception and more diverse tactical models, human equity, 90+ round nonfinish causes, AI lifecycle resume/freeze in the app, and the concurrently dirty Home layout remain for follow-up. Stage 8 release gates remain open.
