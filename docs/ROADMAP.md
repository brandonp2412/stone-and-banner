# Eight-stage implementation roadmap

Status: **Stage 1** in progress/completed only when checks below pass. Living checklist; tick items only with evidence.

## Stage 1 — Design + Android bootstrap
- [x] Inspect Glass instructions and existing project; initialize isolated local git.
- [x] Independent rules and original terminology, card glossary, UX and balance hypotheses.
- [x] Kotlin/Compose Material 3 app, navigation, theme, hex preview board.
- [x] UI-independent immutable deterministic engine with baseline JVM tests.
- [ ] \`buildq\` engine tests and release APK pass.
- [ ] Install local release APK and foreground on Samsung S25.
- [x] Commit stage.

## Stage 2 — Deterministic playable board
- [x] Seeded, replayable 19-hex generation with tested inventories, vertex and hot-token constraints.
- [ ] Vertices, edges, legal setup draft, roads/Villages/Towns, economy and actions.
- [ ] Production and seasonal supply, cost validation, undo-before-confirm.
- [ ] UI placement affordances, visible shortages, local turn privacy handoff.
- [ ] Property tests for resource conservation and replay; pass-and-play smoke test.

## Stage 3 — Advanced economy
- [ ] Craft paper, cloth, coin; Town Developments (five tiers each).
- [ ] Caravan routes, ports, contracts and economic pressure.
- [ ] Trade offers and bounded catch-up procurement.
- [ ] Tests covering every cost, downgrade, shortage and exchange rate.

## Stage 4 — Tactics + common defence
- [ ] Knight roles, exhaustion, Reaver Fleet pressure and Invasions.
- [ ] Bandit road disruption, interception, escorts, repair.
- [ ] Out-of-turn reaction windows with resumable state and accessible countdown.
- [ ] Deterministic simultaneous resolution order, replay and edge-case tests.

## Stage 5 — Three balanced strategy decks
- [ ] Fully author and implement 12 unique cards per deck, two copies each.
- [ ] Exhaustive event timing and interaction tests, no instant unearned Victory Points.
- [ ] Seeded multi-agent simulation batch for equity across turn order and paths.
- [ ] Iterative economy and deck tuning using recorded metrics.

## Stage 6 — Pass-and-play production quality
- [ ] Private hand-off, save/resume, accessibility, onboarding, polished art/audio.
- [ ] Fast startup and frame-budget profiling on Samsung S25, no composition jank.
- [ ] Full local match QA with 2–4 players and rotation/resume tests.

## Stage 7 — Online multiplayer (after local parity)
- [ ] Versioned action/event protocol, authoritative deterministic validation.
- [ ] Lobby, reconnect, async windows, conflict resolution, replay integrity.
- [ ] Identity, abuse controls, privacy, opt-in account storage and recovery.
- [ ] Local/offline mode remains available with no login.

## Stage 8 — Review, compliance and release
- [ ] Independent concept/art/text provenance and legal/IP review.
- [ ] Accessibility, balancing, security, store disclosures, signing and regression suite.
- [ ] External beta only after review; **no public store publication beforehand**.

## Definition of done for every stage

Tests in \`buildq\`, a release build, S25 release install and foreground smoke-test after app changes; deterministic fixtures for new rules; updated docs and local commit with verified diff. Never alter unrelated repositories.
