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

## Slice 05 — AI strategy cards and bounded reactions (4 November 2026, NZDT)

- [Factual handoff](AI-SLICE05-HANDOFF.md), [screenshot manifest](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-05/SCREENSHOT-MANIFEST.md) and [Glass run evidence](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-05/RUN-EVIDENCE.md).
- Source: `lib/engine/ai_cards.dart`, adapter and heuristic integration, empty Bandit-victim reducer guard, and nine new regression tests. Draws remain deterministic reducer events; no rival concealed data is consulted.
- `buildq` isolated **#4775** passed 94 tests, **#4776** analyzer passed, **#4777** release APK built; rebased onto Slice 04 and combined **#4778** passed 106 tests, **#4779** analyzer passed without issues, **#4780** release APK built. No UI screen was opened, no interaction performed, no screenshot produced; no visual QA or Waydroid smoke was claimed.

## Slice 08 — seeded AI stability and fairness (4 November 2026, NZDT)

- [Glass run evidence](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-08/RUN-EVIDENCE.md), [per-action screenshot manifest](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-08/SCREENSHOT-MANIFEST.md) and [90-round capped seeds](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-08/CAPPED-MATCHES.md).
- `tool/ai_stability_corpus.dart` checks every accepted event for resource/card conservation, legality, score/victory consistency, replay equality and bounded progress. Seed ranges 7200–7279 and independent 7600–7799 produced **1,120 three-/four-seat matches, 1,023,024 accepted events, zero invariant/replay/timeout failures**, and 51 matches censored at 90 rounds. An additional 96 paired runs reproduced **96/96 ordered-event fingerprints**.
- Four-seat all-AI opening seat won **88/280** (31.4% vs 25% equal-seat baseline), a bot-model balance risk requiring stronger controlled study before rule changes. A legal-random input simulator is not real human testing. Two-seat matches are **unsupported** by the current reducer; do not claim two-seat coverage.
- Focused longest-road tie and 15-VP tests **2/2 passed** (#4800); 115 non-golden Flutter tests passed (#4806); analyzer passed (#4813); release APK built only (#4804). Full suite #4803 initially had **one Home golden failure** from concurrent AI UI work; recheck **#4814 passed all 116 tests** after that work updated the golden. Visual inspection still found the Start button obscured at 390×844, so golden success is not UI acceptance. **No actual Linux/Waydroid UI screen was opened or interacted with in this engine-only slice; no live screenshot exists.** No Samsung or public deployment.

## Slice 06/20 — bounded AI turn coordination (4 Nov 2026)

- Pure-Dart sequential coordinator: one reducer-validated event per asynchronous tick, one in-flight pump, bounded turns, cancellation generation guard, illegal-choice fallback, malformed-state stop.
- Flutter integration: lifecycle/navigation cancellation, private computer-turn progress, local replay + AI-seat persistence and restore/resume.
- Glass Waydroid offline APK walkthrough: 21 timestamped captured and visually inspected screenshots, each action/expected/actual/verdict in [screenshot manifest](/home/brandon/.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-06/SCREENSHOT-MANIFEST.md). Photos include computer progress and return-to-human privacy handoff. Screenshot 08 was taken before frame settlement; 09/10 establish outcome.
- Tests: pure coordinator #4781 passed; focused widget integration #4833 passed after concurrent setup UI change; full suite #4808 passed (116 tests) before subsequent concurrent setup controls; final full-suite #4836 passed after setup controls and golden refresh #4835. Linux release APK build #4810 passed and installed solely on Glass Waydroid.
- Visual change: compact target chooser modal (before screenshot 07, after screenshot 16). Remaining issue: human action panel remains too dense at 1792×1008 (screenshot 19).
- See also local [run evidence](/home/brandon/.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-06/RUN-EVIDENCE.md). No Samsung or public deployment.

## Slice 07/20 — human versus AI setup UX (4 Nov 2026)

- Material 3 mode selector for **Hot-seat / Vs AI**; 3-player games support **1–2 AI seats** and 4-player games **1–3 AI seats**. Human names are editable, computer seats named deterministically, and Start is visible above collapsed name/seed options. There is no unsupported difficulty setting.
- A solo human no longer receives a redundant privacy gate when play returns from a computer seat; multi-human pass-and-play handoffs and LAN entry remain.
- Glass buildq **#4829**: 3 focused setup tests passed; **#4837**: **119 full Flutter tests passed** initially; after correcting the saved-match button label, **#4848 passed all 120 tests**, **#4849** analyzer clean and **#4850/#4851** Android/isolated-Linux release builds passed; **#4843**: analyzer no issues; **#4830**: Android release APK built and installed on Glass Waydroid.
- Original checkout has no Linux desktop host (**#4823** failed). Isolated nonrepo Linux scaffold built successfully (**#4842**), and its actual headless Wayland app was keyboard-operated and screenshot-reviewed. Mode selection and private handoff were observed; name typing was not tested.
- [28-row per-action screenshot/visual manifest](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-07/SCREENSHOT-MANIFEST.md) and [exact run evidence](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-07/RUN-EVIDENCE.md) on Glass. First black frames were marked failed and recaptured. Shared Glass Waydroid was concurrently controlled, so 3-AI tap, Android keyboard input and complete human-AI game were **not** claimed. No Samsung or public deployment.

## Slice 09 — live AI E2E and 15-point victory (4 November 2026, NZDT)

- [Per-action screenshot and visual verdict manifest](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-09/SCREENSHOT-MANIFEST.md) and [full factual run evidence](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-09/RUN-EVIDENCE.md), recorded directly on Glass.
- Rebuilt Waydroid release in isolated Android user 10: one human plus two AI seats, human setup Village/Road, two automatic computer drafts, reverse draft, seeded roll, human End Turn, AI turns, and return to human at Round 2. Restart resumed the same match.
- A separate **genuine deterministic replay** from 381 previously accepted engine events (seed 914) was imported through the installed APK's UI. A human chose Upgrade → legal Junction 42; the reducer applied event 382, Bot-0 advanced 12→15 VP, and the actual UI rendered **`Bot-0 wins! 15/15 VP`**. Force-stop/relaunch and Continue preserved the finished state. This is **not** an AI autoplay victory from the live human+AI match and does not prove live UI coverage of Bandit/Invasion/tactical phases.
- `buildq` #4840: 120 Flutter tests passed; #4826 analyzer clear; #4839 release APK built; #4845 Linux release built and launched in isolated Cage with a captured real window. Generated Linux runner committed for future reproducibility.
- Visual notes: small-screen Start control remained visible and readable; the legal target list is lengthy and action phase is button-dense below the fold. Earlier stale-build/mistap/import failure screenshots remain in the manifest with honest verdicts. No Samsung/public deployment.

## Slice 10/20 — cross-platform screenshot harness (4 November 2026, NZDT)

- [Reusable Glass/Nox Linux/Waydroid protocol](UI-E2E-PROTOCOL.md),
  [harness](../tool/e2e_screenshot_harness.py) and
  [six offline harness tests](../tool/test_e2e_screenshot_harness.py).
- [Exact run evidence](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-10/RUN-EVIDENCE.md),
  [12-row Linux screenshot/action manifest](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-10/linux-glass/SCREENSHOT-MANIFEST.md),
  [9-row Glass Waydroid screenshot/action manifest](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-10/waydroid-glass/SCREENSHOT-MANIFEST.md).
  All **21 real screenshots** were visually inspected; per-row expected/actual,
  timestamps, platform/build tags, input coordinates/keys, critique, severity,
  verdict and retest details are in append-only JSONL and Markdown manifests.
- Two independently observed **PASS** flows on Glass Waydroid: Home → Vs AI →
  four seats → three AI selection, and Rules → Home with setup preserved.
  Linux additionally proved private handoff → Round 1 board (PASS);
  exploratory Home keyboard traversal had ambiguous focus/route and is LIMITED.
  One initial Android launch failure is retained and retested; the final Home
  key restored the Waydroid launcher. No saved game was overwritten.
- Glass buildq **#4852** isolated Linux release built and screenshot-tested;
  **#4869** 122 Flutter tests passed; **#4870** analyzer clean;
  **#4871** Android release APK built only. Six Python harness tests passed.
  No Nox execution, Samsung, public deployment, or full 3-AI match claimed.
  Minor focus-visibility/landscape-density and APK-version drift remain.

## Slice 11/20 — Home, Rules, offline setup polish (4 November 2026, NZDT)

- [Run and buildq evidence](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-11/RUN-EVIDENCE.md), [53-row action/screenshot/visual verdict manifest](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-11/SCREENSHOT-MANIFEST.md) and adjacent timestamped PNGs. All 53 actual Linux/Glass Waydroid screenshots visually inspected.
- Home focused into a single New local match CTA, while seat/mode/AI and advanced player/seed setup moved to a dedicated Match setup page. Rules advanced/glossary are progressive disclosure; replay parser text no longer leaks through error snackbar; saved-match replacement prompts confirmation.
- **PASS:** buildq #4877 Android release, #4882 123 Flutter tests, #4883 analyzer clean, #4884 isolated Linux release; Waydroid start/resume/back/rules/glossary/AI setup/invalid replay and Linux keyboard Home → LAN are screen-evidenced.
- **LIMITED:** no full LAN session, complete AI match, valid replay import, all board actions, or comprehensive accessibility/landscape test. Initial transient Android launch failure and missed tap retained in manifest. Concurrent board-screen changes intentionally excluded from this slice commit.

## Slice 15/20 — all 54 Strategy Card copies and reactions (4 November 2026 NZDT)

- [27-row real Linux screenshot/action/visual-review manifest](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-15/SCREENSHOT-MANIFEST.md) and [exact build/test handoff](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-15/RUN-EVIDENCE.md) on Nox. Failed/limited window frames retained, then reframed and screenshot-retested.
- Pure reducer matrix: **54 physical cards, 352 legal option/event combinations**, physical-copy/stock conservation, replay-safe duplicate rejection, zero-bank unplayability and no stalls, Governance targeted counter/pass/timeout paths. Added guard for card play with pending standing offers.
- UI: grouped exchange/target selection, explicit Play confirmation, discard confirmation and compact simple-card sheet. Real Linux release imported a deterministic 89-event replay, opened Founding Charter, canceled discard then played; hand 1→0, brick 0→1, coin 1→2.
- Final Nox buildq **#4536**: 128 Flutter tests passed; **#4537** analyzer clean; **#4535** Linux release passed; **#4538** Android APK built with Nox JDK 21 environment override. No Android APK installation claimed.
- **Limits:** Glass connector HTTP 429; Nox Waydroid user 10 already shared with Slice 12, so no Waydroid UI actions/screenshots. Exactly one named card got live Linux detail/play captures, not all 54 dialogs; tactics were reducer-tested, not live UI-tested. No Samsung or public release.

## Slice 18/20 — accessibility, navigation and responsive UI (4 November 2026 NZDT)

- [33-row real Linux/Waydroid read-only screenshot/action visual manifest](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-18/SCREENSHOT-MANIFEST.md) and [build/test/limitations handoff](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-18/RUN-EVIDENCE.md) saved on Nox. Every Linux screen/open/navigation/action captured; all 33 PNGs visually inspected and given an explicit PASS, FAIL or LIMITED verdict with follow-up decision.
- Setup is responsive at high text scale and very narrow widths; Main Home CTA now visible earlier. Page-specific keys repair Rules scroll-offset leakage; Escape keyboard back respects navigation/modal rules. Match actions prioritise full-width End turn and collapse secondary Knight/development complexity.
- Nox buildq **#4562: 137 full tests pass**, **#4566: analyzer zero issues**, **#4564: Linux release**, **#4565: Android release APK built but not installed**; Home golden updated via **#4561**. The earlier #4563 analyzer lint was fixed.
- Actual isolated Linux desktop 1280×800 and 390×844 viewport Home→setup→AI→Rules→Escape/Board-empty visually proved, plus CTA hover/focus checks; 320×640/1.6× light and 390×844/2.0× dark layout/keyboard assertions were **widget tests**, not actual themed-device screenshot proof.
- **Limits:** Glass unavailable/off; Nox Waydroid Android user 11 in use, untouched. One read-only screenshot is of old APK. Dark GTK/DPI attempts produced pixel-identical normal-light captures, so actual dark/large-text visual QA, phone safe areas/orientation/touch semantics and TalkBack remain unverified. Focus outline subtle. No Samsung or public release.

## Slice 17/20 — persistence, replay, crash recovery (4 November 2026 NZDT)

- [35-row real Linux screenshot/action and visual-review manifest](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-17/SCREENSHOT-MANIFEST.md) and [exact build/test handoff](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-17/RUN-EVIDENCE.md) saved on Nox. Every opened Linux screen/action captured; all 35 PNGs individually inspected, including black/clipped/transitional captures followed by corrected frames.
- Saved-match replay import now requires explicit replacement confirmation, warns AI-seat metadata is not carried by shared codes, and leaves the original game untouched on cancellation. Raw JSON replay imports now enforce the existing compact-code 1 MiB UTF-8 decoding limit. Regression tests cover cancellation/confirmation, corrupt session fallback and invalid/oversized data.
- Actual isolated Linux release: Village + Road created exactly two persisted events, stop/cold restart restored Player 2 private handoff without duplicate events, copy/paste replay reached replacement confirmation, Keep preserved original save. A separate valid 89-event compact replay imported after confirmation, and its saved event sequence/seed exactly matched the original deterministic fixture. Targeted SIGKILL of the isolated app and cold restart restored the same Round 7, Bot-1, 2-VP board with all 89 events intact.
- Nox buildq **#4544** focused tests passed, **#4545** full suite **131 passed**, **#4546** analyzer zero issues, **#4547** Linux release built, **#4548** Android APK built with a Nox JDK 21 override (not installed).
- **Limits:** Glass connector 429; Nox Waydroid Android user 11 already running Stone & Banner and not disturbed, so no Waydroid/rotation/background, actual Android crash, or new victory/rematch screen proof. Linux hot-seat and imported manual continuation were observed; all-AI long-play remains supported by prior pure-Dart tests, not freshly observed on a device here. No Samsung or public release.

## Slice 16/20 — authoritative LAN host/guest E2E (4 November 2026 NZDT)

- [74-image screenshot/action/visual manifest](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-16/SCREENSHOT-MANIFEST.md), [run evidence](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-16/RUN-EVIDENCE.md), and [concurrent wire results](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-16/wire-adversarial-results.json) on Nox.
- Two independent Linux GUI clients completed a 3-seat LAN draft (12 accepted setup events), both rolled and saw authoritative snapshots through revision 16; guest app restart resumed saved credentials. Host crash/restart **did not** recover in-memory room; both showed `Room not found.`. Invalid room and concurrent stale/wrong-seat moves were rejected.
- Glass connector HTTP 429; Nox Waydroid bridge TCP verified with temporary narrow firewall rule, then removed. **No Waydroid GUI E2E** and no Samsung/public deployment. Screenshots include black transitional frames retained as failures.
- Nox buildq **#4549** LAN smoke passed, **#4550** 131 tests passed, **#4551** analyzer clear, **#4552** Linux release passed, **#4554** Android release passed with JDK21 environment-only override after initial #4553 JDK17 path failure. Source unchanged; unresolved UI density, stale room-loss state and host persistence gates remain.

## Completion 6/8 — durable LAN recovery and cross-machine GUI (5 November 2026 NZDT)

- [Full LAN recovery test and screenshots handoff](LAN-RECOVERY-E2E-20261105.md).
- Glass host + Nox guest on actual private LAN: GUI room create/join/start,
  four legal opening actions, host process restart and guest app restart,
  preserved board/turn and recovery token. Both hidden Linux GUIs and source
  builds are independently identified in that handoff.
- Glass buildq #5045 wire-restart test passed through revision 18,
  #5046 existing smoke passed, #5051 all 140 Flutter tests passed, #5052
  analyzer clean, #5053 Linux and #5054 Android releases built. The GUI
  cross-machine run did not reach 15 VP; full-game network acceptance remains.
- No persistent test service, nft port opening, public deployment or physical
  device install was left behind.

## Slice 20/20 — final independent release-quality audit (5 November 2026 NZDT)

- [40 ordered Linux screenshot/action/visual-review rows](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-20/SCREENSHOT-MANIFEST.md) and [exact run evidence and acceptance matrix](../../.local/state/stone-and-banner/e2e/stone-banner-ai-e2e-20/RUN-EVIDENCE.md) on Nox fallback.
- Nox buildq **#4568** analyzer clean, **#4569** 137 Flutter tests passed, **#4570** Android release built only, **#4574** Linux release built, **#4575** three-socket LAN protocol smoke passed, **#4577** deterministic pre-win fixture regenerated.
- Actual isolated Linux release GUI proved one-human/two-AI setup, opening draft, human dice, full AI turn cycle and Round 2 save/resume. Separate real GUI imported a reducer-generated 1,143-event pre-win replay, manually upgraded Town Junction 42 to Capital, and rendered **Bot-0 wins! 15/15 VP**. **This is fixture victory UI proof, not a naturally played human-versus-AI victory.**
- Glass connector HTTP 429; Nox Waydroid user 11 occupied by another session, so **no Waydroid installation/launch**, 2-GUI LAN, fresh card/trade/reaction UI, rematch, or full natural 15-VP game was proved. Stage 8 release gates remain open.
