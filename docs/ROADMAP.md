# Eight-stage implementation roadmap

- [x] **1. Flutter foundation:** new Nox Flutter Material 3 project, 19-hex preview, deterministic Dart engine, tested Home/Board/Rules, 15-point scoring and reaction/catch-up baseline. A release APK and Waydroid smoke test must be verified before calling this fully done.
- [x] **2. Playable board:** legal vertices/edges and roads, setup, actions, production, trades, resource conservation, seed/event replay and local pass-and-play.
- [ ] **3. Advanced systems:** commodity production, five tiers of Town Developments, Knight and Reaver Fleet rules, Invasion, Capital races and bounded drought recovery.
- [ ] **4. Three strategy decks:** original green Innovation, yellow Commerce, blue Governance cards and deterministic effect tests.
- [ ] **5. Out-of-turn play:** offers, counters, escorts, tactical reactions, replay-safe windows, privacy and deadline behaviour.
- [ ] **6. Multiplayer architecture:** retain offline hot-seat, LAN/server-authoritative state protocol, reconnect, no unapproved public hosting.
- [ ] **7. Balance:** seeded simulation, strategy equity, comeback rates, first-seat advantage, property and regression tests.
- [ ] **8. Harden:** original art, accessibility, release/UI validation, user device QA and IP/security checks, no public store publication without approval.

Each stage requires `flutter analyze`, `buildq --wait -- flutter test`, release build, Nox Waydroid smoke test, evidence and local commit. Do not mark incomplete features done.
