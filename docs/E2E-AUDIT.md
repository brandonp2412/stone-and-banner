# Stone & Banner — end-to-end audit index

This file indexes independently verified slices. Historical evidence is not
implicitly revalidated by a later slice.

## Slice 01 — local UI baseline (4 November 2026, NZDT)

- [14-row screenshot manifest](evidence/ai_slice01/SCREENSHOT-MANIFEST.md)
  covering the actual local Waydroid release app, setup, private handoff,
  legal board actions and replay resume.
- Captured UI evidence belongs to slice 01; slice 02 did **not** reopen it.

## Slice 02 — pure Dart AI legal-action interface (4 November 2026, NZDT)

- Scope: `lib/engine/ai.dart` and `test/ai_legal_actions_test.dart`.
- [Slice 02 screenshot manifest](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-02/SCREENSHOT-MANIFEST.md)
  on Glass, also at
  `/home/brandon/.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-02/SCREENSHOT-MANIFEST.md`.
- UI screens opened: **none**; UI actions: **none**; screenshots: **zero**.
  Visual inspection is inapplicable to this engine-only slice; no Linux or
  Waydroid app was launched. No Samsung device was used.

### Implemented

- `AiActionAdapter.observe(match, seat)` authorizes the active seat or
  tactical responder and returns immutable public scores, that seat's own
  hand/goods, and finite legal event candidates. It does not return
  `MatchState`, another seat's cards/stores or deck order.
- Candidate enumeration uses the existing engine legality methods for setup,
  dice, construction, upgrades, Town developments, Knights, bank trades,
  strategy cards, tactical pass/counters/aid, invasion and end turn.
- The bot omits private-inventory-dependent Bandit theft targets and
  resource-seizure card targets instead of inferring hidden hands; null-victim
  Bandit moves, explicit discard, pass and End Turn remain available. Trade
  offers are bounded to 1-for-1 candidates because the reducer permits
  unbounded positive requested quantities. Therefore this is a **sound
  finite subset**, not a claim of exhaustive move enumeration.
- `decide(view)` is deterministic for saved match seed, seat, and event
  ordinal; it forces End Turn after eight post-roll events.
  `applySelected` rechecks seat, phase, event ordinal, allowed event payload,
  and always delegates actual validity to `MatchEngine.apply`.
- The Glass Android build's stale Gradle Java home was changed from absent
  JDK 21 to installed JDK 17. No UI code was modified.

### Verification on Glass

Using `/home/brandon/.local/share/flutter-stone-and-banner-3.47.6/bin/flutter`
(Flutter 3.47.6, Dart 3.13.5), scheduled with `buildq`:

| Command (after `buildq --label … --`) | Result |
| --- | --- |
| `flutter test test/ --reporter expanded` | **#4736 passed: 84 tests**, including seven slice-02 tests |
| `flutter analyze lib/engine/ai.dart test/ai_legal_actions_test.dart` | **#4737 passed: no issues** |
| `flutter build apk --release` | **#4732 passed: 54.4 MB release APK** (build only, not installed) |

The slice tests assert reducer acceptance of generated candidates, reject
unauthorized/stale moves, compare decisions against opponent hidden-hand
mutations, exercise explicit discard/pass and finished-game behavior, and
simulate six seeded 3-/4-seat games without deadlock through nine rounds or
victory. Each simulation's replay snapshot matches its applied event log.

Earlier attempts #4717/#4718 could not resolve the default Dart 3.13.4 against
the repo's ^3.13.5 requirement; #4727 exposed the missing JDK 21 path.
The intermediate #4731 run found one overstrict test assertion, corrected
before the successful #4736 run. A full-tree analyzer run #4726 additionally
reported a lint in concurrently edited `lib/engine/heuristic_ai.dart`;
that file was not changed in slice 02.

### Remaining boundaries

- The adapter is not yet wired into Flutter's gameplay UI or the separate
  heuristic policy under concurrent development.
- No UI screenshot, visual QA, Android installation, device interaction, or
  full bot-versus-human playtest is claimed for this slice.
- Hidden-inventory-dependent targeting remains deliberately unavailable to
  this AI interface. A future authoritative blind-choice engine event would
  be needed to support those actions without exposing rival hands.
- Earlier Stage 8 signing, accessibility, security, IP and publication gates
  remain open; see [Stage 8 evidence](STAGE8-EVIDENCE.md).


## Slice 03 — offline heuristic strategy (4 November 2026, NZDT)

- Scope: [AI strategy](../lib/engine/heuristic_ai.dart),
  [seeded tests](../test/heuristic_ai_test.dart), and
  [reproducible benchmark](../tool/ai_strategy_benchmark.dart).
- [Screenshot manifest](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-03/SCREENSHOT-MANIFEST.md)
  and [run evidence](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-03/RUN-EVIDENCE.md)
  are saved on Glass under
  `/home/brandon/.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-03/`.
  **UI screens opened: none; UI interactions: none; screenshots: zero.**
  This was an engine-only implementation/QA slice; no visual inspection,
  Waydroid installation, or on-device AI interaction is claimed.
- The deterministic `HeuristicAi` evaluates productive numbered terrain,
  output variety, opening settlement spacing, road access to future sites,
  Village/Town/Capital VP, Commerce development, bank trade surpluses, and
  tactical response options. The policy consumes the committed
  `AiActionAdapter` whitelist and the test/benchmark dispatch through
  `AiActionAdapter.applySelected`; no new dice or reducer rule was added.
  Rival hidden hands and hidden-target-dependent Bandit/card moves are not
  consulted.
- `buildq` **#4741**: 85 tests passed (7 new strategy tests including
  seeded setup comparison, VP upgrade/capital, resource conservation,
  private-inventory invariance and replay). **#4742**: full
  `flutter analyze lib test tool` passed, no issues. **#4744**:
  `flutter build apk --release` passed (54,398,538 bytes,
  SHA-256 `3f57b11e25d17e00780a2a1ceb8348a8f169831c603f38ee6d7340a43f4df372`);
  built only, not installed.
- `buildq` **#4743**: 24 seeded games (601–624, up to 65 rounds), heuristic
  seat average **10.375 VP**, legal-random opponents average **2.542 VP per
  seat**. The heuristic won **9** matches; **15** had no winner by the
  round cap. Actions included 154 roads, 101 villages, 418 upgrades,
  and 434 bank exchanges. This shows a nontrivial legal move policy
  outperforming that seeded random baseline on score, **not** human-level
  strength or an overall competitive win-rate claim.
- Verification used Glass's isolated Flutter 3.47.6 / Dart 3.13.5 SDK,
  because the default wrapper currently reports Dart 3.13.4 and cannot
  satisfy the repository's `^3.13.5` constraint.

Remaining: integrate AI seat selection and turn-running UI in a later
slice, then capture every new AI screen and interaction on Linux/Waydroid.
Add stronger human-like opponents, defensive Knight planning and larger
balanced-seat simulations before drawing conclusions about match equity.
Stage 8 publication, accessibility and physical-device gates remain open.

## Slice 04 — advanced AI strategy (4 November 2026, NZDT)

- Scope: public/own-seat `AiStrategySignals` and a deterministic advanced
  decision layer in [the legal-action adapter](../lib/engine/ai.dart),
  [heuristic opponent integration](../lib/engine/heuristic_ai.dart), and
  [scenario tests](../test/ai_advanced_strategy_test.dart).
- [Screenshot/action manifest](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-04/SCREENSHOT-MANIFEST.md)
  and [run evidence](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-04/RUN-EVIDENCE.md)
  are saved on Glass at
  `/home/brandon/.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-04/`.
  **UI screens opened: none; UI interactions: none; screenshots: zero.**
  This slice changed only pure Dart AI and tests; no Linux/Waydroid app was
  opened or interacted with, so visual verdict is not applicable.
- The AI evaluates actual Town/Capital productive pips (without inventing
  seasonal production multipliers), Town Development track effects, impending
  Reaver threat, legal Knight activation/promotion/recruitment and enemy Knight
  displacement, fortification damage absorption, public Invasion aid gap,
  dry-roll recovery prospects and stock-backed catch-up bank trades. Choices
  use only public state and the acting seat's private data; actual validity,
  bank stock, costs and victory remain reducer-owned. No new rules/servers.
- The heuristic opponent honours a deterministic eight-event action cap.
  New tests exercise tactical aid/pass, development production and Commerce,
  Knight/fortification plans, catch-up and empty bank, Aqueduct drought
  investment, hidden-hand invariance, finished/cap behavior, conservation
  and deterministic seeded replay.
- Verification on Glass (Flutter 3.47.6, Dart 3.13.5): buildq **#4770**
  full `flutter test test/`: **97 passed**; **#4771**
  `flutter analyze lib test tool`: **no issues**; **#4772**
  Android `flutter build apk --release`: **passed**, build only;
  **#4773** seeded benchmark (24 games, seeds 801–824, max 50 rounds)
  heuristic **7.667 VP/seat**, legal-random rivals **2.604 VP/seat**,
  **3/24 finished and won by heuristic**. Benchmark is a limited
  random-opponent comparison, not competitive strength or human balance proof.
  Post-QA aid-edge and Capital-goal fixes received final reruns as documented in RUN-EVIDENCE.md.
- No gameplay UI integration, device smoke test, network session, public
  deployment, Samsung test or visual QA was claimed here. Stage 8 external
  release gates remain outstanding.
