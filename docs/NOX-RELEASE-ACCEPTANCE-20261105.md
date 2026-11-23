# Stone & Banner — Nox integration and release acceptance, 5 November 2026

**Verdict: integrated candidate, NOT release-ready.** Work was confined to Nox; no Glass or Samsung interaction, public release, store upload, remote push or production installation.

## Ownership and integration

- Read `/home/brandon/AGENTS.md`, repository `AGENTS.md`, `docs/ROADMAP.md` and `docs/RULES.md`. The Nox main checkout remained at `f36c843` with its pre-existing uncommitted change to `docs/E2E-AUDIT.md`; it was not edited, reset, stashed or merged into.
- Prompta's visible queue contained no active Stone & Banner job. Nox buildq had no active task at integration start. A separate old Nox Linux app process was left alone. All integrations used `/home/brandon/.local/state/stone-and-banner/integration.lock` and the isolated persistent worktree `/home/brandon/.worktrees/stone-release-acceptance-nox-20261105`.
- Started at `fdb5083` (mobile action UX, card/trade/reaction GUI tests and Android accessibility). Earlier `7e77282` and `c395622` are ancestors of this branch, so were not applied twice.
- Merged `0cdfe0b` four-player AI/resume (merge `b394aeaf9b3e32c1083455b6ac9d646fa9e467f0`), `e4266d0` fairness simulation (merge `f2ed1fcaa3c41b71bb1729ad2841e93c41b9c99e`) and `048aa7f` LAN persistence (merge `f864f13959458c86b03a73a90d4c32f0265a20bb`) without conflicts. Tested integrated source HEAD **`f864f13959458c86b03a73a90d4c32f0265a20bb`**, with clean tracked status before adding this evidence.
- A distinct natural-match completion branch was not present in Nox's enumerated Git refs. No active owner was displaced. Upstream `main` has **not** been advanced.

## Nox buildq verification (same integrated source)

| ID | Check | Result |
| --- | --- | --- |
| `#4780` | `flutter analyze lib test tool` | PASS, zero issues |
| `#4781` | `flutter test test/ --reporter expanded` | PASS, **161/161** tests |
| `#4782` | `dart run tool/lan_recovery_smoke.dart` | PASS: three actual sockets, 12-event draft, host kill/restart, persisted decisions/deduplication, guest reconnect and three turns to revision 18 |
| `#4783` | `dart run tool/lan_smoke.dart` | PASS: authority, filtered state, deduplication and reconnect |
| `#4784` | `flutter build linux --release` | PASS; `libapp.so` SHA-256 `d41f55084f1c7de7651bf0206a036860c322e15f24c` |
| `#4785` | Java 21, `flutter build apk --release` | PASS: 54,955,834 bytes, SHA-256 `743b4fe9a061908b247c6986f6b33c1913abd3cdf2e5787a12aed16809b724da` |

The Android artifact was independently inspected using SDK 37 `aapt2` and `apksigner`: exact package ID `nz.presley.stoneandbanner`, versionCode **8**, versionName **0.8.0**, minSdk 24, targetSdk 36 and APK v2 signature verification PASS. **The signer is `CN=Android Debug`**, certificate SHA-256 `9be80f8136f29c4137394cf9f62aa9219d6e28b19f14bf9ff609534d791f8693`; this is a public-release blocker, not a production signing approval.

## Direct Nox Linux GUI acceptance

- Launched the fresh integrated Linux release under dedicated Xvfb display `:187` and separate XDG data/config/cache, without interacting with the existing Nox app or any device.
- Visually inspected Home, new match, **one human + two AI** setup, the seeded 19-hex board, human Village and Road placement, automatic AI snake draft, the human's second Village and Road, Round 1 roll, human action phase, AI turns to Round 2, and the human's legal Bandit move in Round 3. The second Human Village was 2/15 Renown; save/restart restored the same game through `Continue saved match`.
- Curated **12 real screenshots** are in [`evidence/nox-integration-20261105/`](evidence/nox-integration-20261105/) (Home/setup/draft/restart/resume/placements/roll/action/Bandit). Source screenshots and app/Xvfb logs are retained in the private Nox state path `/home/brandon/.local/state/stone-and-banner/e2e/nox-integration-20261105/`; no private replay or hands were committed.
- Bounded desktop GUI autoplay attempted natural continuation with human button clicks, no injected replay state or fixture victory. `#4788` was stopped by a screenshot-button colour mismatch in the **test harness**, not the app; `#4789` reached a genuine Bandit prompt, then the human moved the Bandit through the GUI. `#4790` advanced the same saved game to **542** accepted replay events; `#4791` advanced it to **924** accepted events (73 more GUI button actions), including recorded rolls, offers/answers, Roads, Town upgrades, Guard actions, tactical windows, Bandit moves and Invasions. See the sanitized `autoplay3-actions.jsonl` and `autoplay4-actions.jsonl` step logs in the evidence directory.
- **No natural 15-Renown win/defeat screen was reached** within the bounded GUI run. The earlier imported pre-win fixture and AI simulations are not substituted for this missing proof. No complete human-versus-AI match, rematch or replay-copy/import UI flow was newly accepted on Nox.

## Remaining gates — do not publish

1. **Game-over:** Finish a genuine human/AI match to 15 Renown with screenshots and reducer-replay equality. The long deterministic GUI run reached 924 events without a witnessed winner; investigate late-game AI progress or rule stalls before claiming acceptance.
2. **Complete live action matrix:** Fresh Nox live GUI evidence for actual Strategy Card choice/play, trade acceptance/counter/escrow, Guard intercept, political reaction, Invasion aid and game-over; the imported-fixture GUI and unit/widget coverage on feature branches are narrower.
3. **LAN UI:** Fresh integrated two-real-GUI-client game with host restart and mid-game guest reconnect, plus full game to victory and timeout observation. Socket recovery passed on Nox; the previously recorded Glass↔Nox two-GUI evidence predates this combined candidate and cannot be rerun while Glass is off.
4. **Android:** Nox Waydroid Android user 11 is visibly occupied by `nz.presley.stoneandbanner.mobileuiqa`; it was not installed over, navigated or force-stopped. No separate emulator/AVD was installed on Nox. Fresh integrated Android screenshot/TalkBack/font-scale/device-lifecycle acceptance is deferred. No Samsung interaction.
5. **Distribution security/legal:** Debug signing blocks release. LAN intentionally uses cleartext `ws://` and `usesCleartextTraffic=true`; do not expose the host outside trusted LAN. Android backups are disabled; host-only room checkpoints have private tokens and require protected local storage. Repository root has **no app-source LICENSE** (only `assets/fonts/LICENSE`). Privacy disclosures, art/trademark clearance, production key provenance and publication review remain open.

No source balance parameters, package ID, signing configuration or version numbers were changed. No public hosting, cloud SDK or new account/service was introduced.
