# Stone & Banner — Slice 15/20 factual run evidence

Date: 4 November 2026 NZDT. Host: **Nox** fallback. Started on `main` at `126b99a` with a clean worktree, after reading `AGENTS.md`, `docs/ROADMAP.md`, `docs/RULES.md`, Stage 4/5/8 evidence, and `docs/E2E-AUDIT.md`. Glass execution was attempted twice and returned MCP HTTP 429; direct Glass proof was not available. Nox checkout was visibly at Slice 11, not assumed to include untransferred Slice 12–14 changes.

## Implemented in this slice

- The pure reducer now disallows card play while any standing trade is pending. Discard/end-turn remain available. The UI continues to derive playable targets directly from reducer enumeration.
- Strategy Card detail separates choosing an option from committing it. Trade cards group by offered good; seizure cards group by rival; a selected choice needs explicit **Play selected card** confirmation. Discard uses a separate **Discard this card?** confirmation with Keep card / Discard. Short/simple sheets use a compact height to eliminate the 78%-height one-option blank area observed in the first Linux run.
- New deterministic `test/ai_slice15_cards_matrix_test.dart`: 54 physical copies (18 per deck), **352** unique legal play choices accepted by the real reducer, conservation of all 8 goods and physical-copy accounting, duplicate/stale rejection, zero-bank unplayable cards still discardable/end-turn-safe, standing-trade guard, and all three targeted Governance attack/counter/pass/timeout variations. The matrix uses a controlled seeded state with explicit resource/knight setup, not a full replay-import proof for each option.
- Expanded widget tests check selection is not play, explicit discard Keep/Discard, and grouping/confirmation of an Open Routes exchange.

## Actual buildq results on Nox

| Job | Command / scope | Result |
| --- | --- | --- |
| #4524 | New four-test matrix before guard fix | FAIL as expected: pending trade allowed a play, plus test fixture compared Knight object identity |
| #4525 | Matrix after guard fix | PASS, 4/4 |
| #4526 | Matrix + card widget tests | PASS, 7/7; 54 copies and 352 legal options |
| #4527 | `flutter test test/ --reporter expanded` | PASS, 128 tests |
| #4528 | `flutter analyze lib test tool` | PASS, no issues |
| #4529 | `flutter build linux --release` | PASS |
| #4530 | `flutter build apk --release` | FAIL only due to stale Glass JDK 17 path in existing Gradle properties on Nox |
| #4531 | `dart run tool/stage8_scenarios.dart` | PASS; generated authentic 89-event strategy-card replay under `/tmp/stone_banner_stage8_scenarios/card.code` (953 chars) |
| #4532 | Android release with Nox JDK 21 `GRADLE_OPTS` and `JAVA_HOME` overrides | PASS; no tracked Java-path change |
| #4534 | Focused tests after compact sheet tweak | PASS, 7/7 |
| #4535 | Rebuilt polished Linux release | PASS |
| #4536 | Final full test suite after UI tweak | **PASS, all 128 tests** |
| #4537 | Final full analyzer | **PASS, no issues** |
| #4538 | Final Android release APK with same JDK 21 environment override | **PASS, 54,873,874 bytes** |

Final APK SHA-256: `4f8c005e043086bb0f7ca3dcabdd4b661693dd3c2c700139678fe4452f428921`.
Final Linux `bundle/lib/libapp.so` SHA-256: `25bba4ce131d1ba6d3c6830d22c25099e804011f99b60761f801c8d80c9c9abb`.

## Actual Linux UI evidence

- Real release executable in isolated Xvfb `:45`, 390×844, with its own XDG data/config home. 27 ordered screenshots captured after every opened screen and meaningful interaction; each inspected directly and reviewed in [SCREENSHOT-MANIFEST.md](SCREENSHOT-MANIFEST.md) and append-only `SCREENSHOT-MANIFEST.jsonl`.
- UI steps: Home → Import replay (actual 953-char code) → Bot-1 private handoff → Round 7 actions → Strategy hand 1/4 → Founding Charter detail → select effect → explicit Play → hand 0/4 and brick 0→1, coin 1→2. Repeated after compact-height tweak: discard confirmation opened, Keep card canceled, Play still settled exactly once.
- Initial Xvfb GTK window was 1280px wide and clipped by the 390px display; recaptured after resizing. One transition frame initially lagged. Both failures retained; the revised compact sheet is screenshot #23 and final play screenshot #27. Main board action controls remain dense at phone width, separate from this card-sheet change.

## Important limits

- No Glass runs due to HTTP 429. Nox Waydroid was already running isolated user 10 for Slice 12, so it was **not** switched, installed to or controlled. **No Waydroid screen or action**, and no Waydroid screenshot in Slice 15. No Samsung/public release.
- Real Linux UI captured **one named card** (Founding Charter), not all 54 physical cards; other 53 copies have deterministic reducer test coverage but no individual real-device dialog screenshots. Governance tactical counters and pass/timeout were tested as reducer fixtures, not through live Waydroid dialogs. Full-hand/reshuffle/draw coverage exists in existing Stage 4 tests included in the 128-test suite, not in this live UI walkthrough.
- No live LAN/multi-device tests, and no competitive human balance claim. A possible hidden-resource disclosure risk in targeted seizure options remains for future privacy review; changing its rules was out of scope.
- The Gradle Java path in checkout is tailored to Glass. Nox builds succeeded with an environment override only; project Gradle config was left untouched to avoid breaking Glass.

## Commit and cleanup

Committed validated source/docs on Nox `main` as `2d39c36225ddd6e29fc981f4445429f65cfc7faa` (local branch ahead of `origin/main` by one; not pushed). Screenshots and run evidence remain in the Nox slice-15 state path. The temporary isolated Linux app and Xvfb compositor were stopped after capture; no shared Waydroid user was touched.
