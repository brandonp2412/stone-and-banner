# Stage 6 — LAN rooms and authoritative host

## What works

- Offline hot-seat and its private handoff/replay remain unchanged.
- A Dart server process on **Nox** owns each room's 3–4 seats and match.
  Android clients create/join with a short code, see connected seats, and
  start once full; each socket is bound to exactly one seat.
- All moves run through the unchanged pure \`MatchEngine.apply\` on the host.
  Requests carry \`id\`, \`base\` revision and event. Same ID + payload is
  acknowledged once, even across reconnect; reused IDs or stale revisions
  reject. The client waits for an ack and displays reconnection states.
- Each accepted event advances a monotonic sequence. Reconnecting clients
  receive a fresh authoritative snapshot and a public event history, and the
  host can replay the full private event stream with its secret seed. Clients
  **never** apply a private full-replay or make legality decisions.
- Tactical responders have 20 seconds before the host records
  \`TimeoutTactical\` and continues clockwise. Every other phase has a
  three-minute inactivity fallback: deterministic first legal setup move,
  roll, harmless Bandit move, Invasion resolution or End Turn. This also
  advances disconnected seats so standing escrow never blocks indefinitely.
  Standing offers still expire/refund on the proposer's next action turn.

## Nox host and clients

On Nox, from \`/home/brandon/stone-and-banner\`:

\`\`\`sh
# Waydroid-only, isolated bridge:
dart run tool/lan_server.dart --bind 192.168.240.1 --port 8765

# Or, for other trusted devices on the same Wi-Fi:
dart run tool/lan_server.dart --bind 192.168.1.133 --port 8765
\`\`\`

In the app select **LAN multiplayer room**, enter
\`ws://192.168.240.1:8765/room\` in Nox Waydroid or the Nox Wi-Fi IP
(\`ws://192.168.1.133:8765/room\` currently) on other devices, choose
**Create room**, copy the invitation code, and let two or three others
**Join room**. The creator starts when full. A device can reconnect to its
seat using its stored recovery token, even after the app restarts, provided
the host process is still running. The room code is not a seat credential.

Nox currently has a default-drop input firewall and TCP/8765 is not permitted. A trusted LAN or Waydroid client requires a separately authorized, narrowly scoped allow rule for this port and source interface. The temporary Waydroid-only rule used in QA was removed afterwards.

The host binds loopback by default. Explicit LAN binding is required.
Do not forward port 8765 or expose it via a public tunnel. No server is
deployed publicly, and no matchmaking or internet relay exists.

## Trust and secrecy

- **Trust the host operator** with all cards, resources, deck order, pending
  thefts and the private seed. A compromised host can see or alter the match.
- The host uses a cryptographically seeded private match seed, separate from
  the selected board seed. Only the explicit 19 public tiles are transmitted.
  Clients receive their own resource types/quantities and held card IDs;
  rival hands and draw/discard deck orders are removed from snapshots.
  Public standing offer terms, scores, development levels, bank stock,
  tactical windows and rival hand **counts** are visible. The server sends
  the active player's legal targeted-card options; those may expose which
  resource *types* are targetable, but not rival quantities.
- A 256-bit recovery token controls each seat. The Flutter client stores
  its token in Android app-private shared preferences (not encrypted).
  \`ws://\` is **not encrypted**; others with LAN traffic visibility could
  intercept the token and take a seat. Use only a trusted private LAN.
  There is no TLS, login, identity verification, abuse protection, room
  moderation or end-to-end secrecy. Not appropriate for public hosting.
- Server memory is authoritative, including private event history. The host
  process must remain alive: an OS restart or server crash currently
  destroys active rooms. There is no durable journal or crash recovery.
  Client reconnection covers socket/app restart, not a server restart.
- The server may advance a disconnected player's turn automatically.
  This is a documented gameplay trade-off; an absent user may lose a turn.
  In-memory requests are idempotent only for the lifetime of that room.

## Verification

\`\`\`sh
buildq --wait -- flutter analyze
buildq --wait -- flutter test
buildq --wait -- dart run tool/lan_smoke.dart
buildq --wait -- flutter build apk --release
\`\`\`

\`test/stage6_room_test.dart\` covers per-seat secrecy, illegal/wrong-seat
events, duplicates/stale revisions, replay, escrow, seed separation, bounded
fallbacks and event decoding. \`tool/lan_smoke.dart\` starts an actual
loopback WebSocket host and three clients for a create/join/start/move,
adversarial rejection, fan-out and reconnect probe.

Remaining work for any internet release: authenticated TLS transport,
persistent server-side storage and recovery, rate limiting, host/fairness
auditing, abuse controls, production deployment approval, and Samsung QA.
