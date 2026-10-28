# Stage 6 verification — Nox, 29 October 2026 (NZDT)

- Canonical Flutter Stages 1–5 verified at clean main 89b8c87; separate Nox worktree; Glass untouched. Android ID nz.presley.stoneandbanner unchanged.
- Dart authoritative room host supports 3–4 seats, join/reconnect tokens, idempotent requests, server legality, sanitized snapshots and public history, private event replay, 20-second tactical deadlines, three-minute idle-turn fallback. Public board layout does not expose the private dice/card seed. Offline hot-seat remains separate.
- buildq #1689: flutter analyze — no issues.
- buildq #1690: flutter test — 62 passed (Stages 1–6).
- buildq #1691: tool/lan_smoke.dart — three WebSocket clients; create/join/start, wrong-seat rejection, legal move, duplicate, broadcast, reconnect passed.
- buildq #1692: flutter build apk --release — passed, 53,838,525 bytes. SHA-256 ec88b7447ca456be0f4038c4df875349ef451afb894ef82adfd7e82611c93e9b.
- buildq #1693: release APK installed on Nox Waydroid 192.168.240.2:5555; cold MainActivity launch succeeded (177 ms).
- Live Android release: created room 34A7D809; two Nox clients joined (buildq #1694); Android started room, placed one Village and Road, reached 1 VP and displayed “Waiting for Ben…”. Android app was force-stopped/relaunched, used saved recovery token and restored that turn. Offline home created a private handoff and playable board, left foreground.
- Nox default-drop firewall initially blocked 8765. A temporary rule restricted to Waydroid 192.168.240.2 → 192.168.240.1 TCP/8765 enabled smoke test; after tests service stone-banner-stage6-smoke stopped and nft rule handle 34 removed and verified absent. No permanent firewall change or public service.
- Screenshot: docs/evidence/stage6_waydroid_waiting.png.
- No physical Samsung install/test; no deployed remote-internet backend. LAN requires an explicit restricted Nox firewall allowance; host process must remain alive as rooms are in-memory. See docs/STAGE6.md for trust model.

- Canonical main post-merge verification: buildq #1697 pub get, #1698 analyze (clean), #1699 all 62 tests, #1700 release APK 53,838,525 bytes with SHA-256 a6154b02625281ee5c0784013bf87f6eb28cc5f2553fffc9bddd4f426d79ac29; buildq #1701 installed this exact canonical APK on Waydroid and MainActivity cold-launched successfully (167 ms). The rebuilt APK byte hash differs from the earlier identical-source worktree release.
