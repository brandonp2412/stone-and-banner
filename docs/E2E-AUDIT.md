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
