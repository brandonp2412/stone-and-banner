# Stage 7 evidence — local test host, 29 October 2026 (NZDT)

- Canonical clean pre-edit `main` was `5cbd57f`; Flutter `lib/` and
  `test/` were verified, root legacy Android left untouched.
- Added deterministic 3–4-seat bot harness using the existing legal-action
  reducer and randomized saved boards. Track focus, trading and defence
  behavior rotate independently; all outcomes use serialized replay events.
  Configured alternatives are immutable and replay-encoded; baseline
  defaults remain unchanged after a contradictory independent confirmation.
- Seeded 120 × 8 paired comparisons via buildq **#1721**; new 240-seed
  independent original-versus-Market-Hall confirmation via **#1722**.
  Compact JSON summaries: `STAGE7-METRICS.json` and
  `STAGE7-CONFIRM.json`; interpretation in `BALANCE.md`.
- Regression/property tests include old replay compatibility, malformed
  parameter rejection, variant replay equality, zero VP granted by the
  catch-up bank trade, per-event supply conservation including escrow,
  no negative stores, deterministic 3-/4-seat games on varied boards,
  bounded tactical responses and reproducible event histories.
- buildq **#1723** full Flutter suite passed; **#1724** real local
  authoritative WebSocket smoke (create/join/legal action/reconnect)
  passed; **#1725** Flutter analyze passed with no issues.
- Production app ID remains `nz.presley.stoneandbanner`; assets and
  original rule vocabulary unchanged.
- buildq **#1726** release APK succeeded: 53,838,525 bytes,
  SHA-256 `0a77ea02b43b0883a5de1bbedd05dcf4a1df2a507d8f3e1e9ffc2c322c784475`.
  local test host ADB installed it successfully on Waydroid
  `<TEST_DEVICE_IP>:5555`; `.MainActivity` cold-launched in 186 ms
  and remained resumed/foreground.
- Live release UI: Home opened LAN multiplayer entry (private local test host host form)
  and returned; an offline three-player match opened its private handoff.
  After Player 1 became ready, tapping a central glowing junction placed
  a legal Village (1/15 VP), and tapping its adjacent side placed a Road.
  The subsequent handoff named Player 2; Player 2 resumed on the board.
  Screenshot: `docs/evidence/stage7_waydroid_board.png`.
- No Samsung QA, remote server, public store distribution, or secondary host use.
