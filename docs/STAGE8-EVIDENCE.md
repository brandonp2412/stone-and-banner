# Stage 8 local release evidence — local test host, 29 October 2026 (NZDT)

**Status: verified local Android release candidate, not approved for public distribution.** All source, builds, tests, git and device actions occurred on local test host at project checkout; secondary host remained off. Flutter lib/ and test/ are canonical; legacy root Android source was untouched. Baseline main was fa18243.

## Shipped

- Original generated basalt-and-banner crest for Home and every Android launcher density; refreshed Material 3 screen goldens and consistent Stone & Banner branding.
- Private on-device replay autosave after game creation/import and each accepted move. Resume or return to board requires a private handoff; corrupt save is handled without app failure. Android app backups disabled to protect hidden hands.
- Text-accessible legal target list for junctions, roads, upgrades and Bandit hexes, preserving canvas input and engine validation.
- Compact sbz1: gzip/base64Url replays, bounded decompression, backwards-compatible raw JSON, copy/import controls. Exports contain all private hands: share only with trusted participants.
- Pure Dart deterministic engine, 3–4-seat offline play, Invasion, Strategy Cards, reactions, player trades, host-authoritative LAN room protocol and 15-VP victory flow remain available. No public server was deployed.

## Automated verification on local test host

| Check | Evidence |
| --- | --- |
| Flutter tests | buildq **#1753**, **71 passed**, including deterministic replay, conservation, autosave/restart/privacy, compact-code hostile inputs, target accessibility |
| Analyzer | buildq **#1755**, zero issues |
| Three-client local authoritative WebSocket smoke | buildq **#1754**, room create/join, authority, duplicate suppression, state filtering, reconnect |
| Android release APK | buildq **#1752**, 54,398,538 bytes; SHA-256 **ba5a2d42b127a6fc609e6f3b6846fa327782d03d0a27f63ddb3aa8b044dd5b37** |
| APK manifest/signing | aapt2: package **nz.presley.stoneandbanner**, label **Stone & Banner**, **0.8.0+8**; apksigner verified **Android Debug** signature (publication blocker) |

Reproduce with buildq --wait -- flutter test, buildq --wait -- flutter analyze, buildq --wait -- dart run tool/lan_smoke.dart, and buildq --wait -- flutter build apk --release. tool/stage8_scenarios.dart generates deterministic replay checkpoints; the moves below were performed in the installed release app's UI, not injected directly.

## local test host Waydroid Android release smoke

Release APK installed and cold-launched via local test host ADB on **<TEST_DEVICE_IP>:5555**; ActivityManager cold-launch about **178 ms**. Tested portrait 432×960 and landscape 1920×1080. Screenshots were captured from the live **release APK**; names below are relative to docs/evidence/.

| Scenario and observed outcome | Screenshot evidence |
| --- | --- |
| Home original crest; live board tap placed Village; legal target list placed Road; private next-seat handoff | stage8_home_landscape.png, stage8_phone_home.png, stage8_village.png, stage8_accessible_targets.png |
| Force-stop/restart offered Resume; private handoff concealed active player; board state preserved | stage8_autosave_relaunch.png, stage8_phone_private_handoff.png, stage8_phone_board.png |
| Invasion fixture: Cora pledged 1 ore for +2 defence; Fleet 4 vs Defence 2 resolved, no Town raid | stage8_invasion_reaction.png, stage8_invasion_resolved.png |
| Dice production credited +1 brick | stage8_roll_production.png |
| Ada escrowed 1 brick for 1 wool; Ben accepted, brick 5→6, wool 3→2, offer cleared | stage8_offer_escrow.png, stage8_trade_accepted.png |
| Governance Town Development tier 0→1 cost 1 wheat and 1 ore | stage8_developed.png |
| Played Founding Charter Strategy Card: coin 1→2, brick 0→1, card left hand | stage8_card_detail.png, stage8_card_played.png |
| Moved Bandit to occupied tile and robbed Bot-1 of a brick | stage8_bandit_stole.png |
| Upgrade Town at Junction 42→Capital: Bot-0 VP 11→14; spent 2 wheat, 2 ore, 1 paper, 1 cloth, 1 coin | stage8_capital_before.png, stage8_capital_targets.png, stage8_capital_upgraded.png |
| Legal Village→Town at Junction 1 won match; live banner **Bot-0 wins! 15/15 VP** | stage8_win_before.png, stage8_victory_15vp.png |

Filtered device logcat for AndroidRuntime:E and Flutter:E returned **no error lines** in the smoke window. Android gfxinfo samples were short and do **not** constitute a valid Flutter engine jank benchmark; no trustworthy long-session frame-pacing measurement was made. UI appeared responsive in manual testing. LAN smoke validated the local three-socket protocol, not separate-device Wi-Fi transport or network adversity.

## Outstanding distribution/quality gates

1. **Signing:** The release-build APK is signed by **CN=Android Debug**. Provision secured production key, provenance and store release checks.
2. **Network/security:** LAN uses cleartext ws:// and Android cleartext enabled; only trusted local networks are supported. No TLS/authenticated public backend, adversarial audit, hosting approval or internet matchmaking. Never publicly expose the current LAN server.
3. **Legal/IP/privacy:** Independent trademark, gameplay expression, original-art provenance/licence, privacy disclosures and publication review missing. Source string audit found no third-party board-game marks in canonical Flutter app and docs, but this **does not** establish legal clearance.
4. **Real devices/accessibility:** No Samsung release install or TalkBack/switch testing; local test host Waydroid only. Contrast under accessibility settings, font scaling, real-device performance and long-session jank remain to be checked.
5. **Balance and deployment:** Prior deterministic simulations exist, but human balance and competitive fairness remain unproven. No public deployment/store upload was attempted.

Stage 8 roadmap checkbox remains unchecked until these external gates are addressed.
