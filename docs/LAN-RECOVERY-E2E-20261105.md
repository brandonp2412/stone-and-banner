# Stone & Banner — Completion 6/8: LAN recovery and E2E

5 November 2026 NZDT. Glass worktree:
`/home/brandon/worktrees/stone-lan-recovery-20261105` on
`feature/lan-persistence-e2e-20261105`, based on `f36c843`.
Other active UI, AI, four-player and reconciliation worktrees were not edited.

## Implemented

- `LanRoomStore` checkpoints each room into its host-only private directory.
  Includes creator/joined seat names, recovery tokens, private deterministic
  seed/replay, ordered public audit, and accepted/rejected request-ID decisions.
  Live socket connectivity is deliberately not checkpointed.
- Every room creation/join, fresh start, acknowledged move decision, tactical
  timeout and idle advancement is synchronously flushed then atomically renamed
  before any success ack/state broadcast. Disk-write failure terminates the
  host rather than confirming unjournaled state.
- Startup reconstructs all rooms and validates checkpoint format, identity,
  replay seed/board/players, audit sequence and request-ID caches. Corrupt or
  inconsistent files block startup; they are never silently discarded.
- Host `--state-dir` overrides private default
  `$XDG_STATE_HOME/stone-and-banner/lan-rooms` (or
  `$HOME/.local/state/stone-and-banner/lan-rooms`). Directory chmod 0700
  on Linux/macOS. These files hold credentials and private cards: **never**
  publish, sync, commit or share them.
- Upon host restart active rooms receive fresh 20-second tactical / 3-minute
  idle timers. Time elapsed while the server was offline is **not** replayed
  as a game event, so the game remains reducer/event deterministic.
- Existing private-LAN-only `ws://` transport and pure reducer stay intact.
  No hosted server, relay, STUN/TURN, account, subscription or cloud SDK.

## Test evidence

| Glass buildq | Result |
| --- | --- |
| #5041 | Focused new and Stage 6 tests, 10 passed |
| #5045 | Host killed/restarted; 3 WebSocket peers, 12 legal setup events, secret filtering, wrong-seat/stale/duplicate checks, guest reconnect, preserved request cache and 3 full turns to revision 18 — PASS |
| #5046 | Legacy three-socket smoke — PASS |
| #5051 | Entire Flutter test folder, **140 passed** |
| #5052 | `flutter analyze lib test tool` — **no issues** |
| #5053 | Flutter Linux release — PASS, executable SHA-256 `eebd9cbcd5a9d4dd037fb3e0dcdf95d31e9288a335fa2abf7cc47acaadb044ba` |
| #5054 | Flutter Android release — PASS, 54,890,298 bytes, SHA-256 `cfbb6b931628dbda8cb5f3c3ce12046818b350c08211742fed5c750212a5fe79` |
| #5067 | Final full Flutter test folder after broad-directory guard, **141 passed** |
| #5069 | Final `flutter analyze lib test tool` — **no issues** |
| #5063 | Third seat joined live GUI room by LAN CLI — PASS |

Intermediate failures were preserved and resolved: #5040 initial test assertion
matcher typo, #5042/#5047 analyzer style warnings, and #5044 test-driver
tactical responder omission. These were not host corruption findings.

### Two real Linux GUI clients across separate trusted-LAN machines

- Host: Glass `192.168.1.102:18876`, explicit private interface.
  Restricted to Glass and Nox `192.168.1.133` during test.
- GUI 1: Glass isolated Xvfb `:157`, new Linux release, dark theme.
- GUI 2: Nox isolated Xvfb `:158`, existing Nox Linux release at
  `f36c843`, light theme. Independent `XDG_DATA_HOME` and
  `XDG_CONFIG_HOME` prevent touching saved personal matches.
- Actual GUI-created room `1AC9E666`: Glass Ada joined as seat 1,
  Nox Ben joined seat 2; third Cora joined with CLI and disconnected.
  Glass creator started the 3-seat match.
- Both GUI windows showed the same public board. Glass clicked a legal
  Village and adjacent Road (authoritative revisions 1/2); Nox's GUI
  showed Ben's turn and clicked its Village/Road (revisions 3/4).
  Both showed those exact coloured sites/roads.
- At revision 4, the Glass host process was **actually restarted**.
  Both still-running GUI clients automatically reconnected. Their
  post-restart screenshots showed the same two Villages/two Roads,
  same Cora turn and no `Room not found` error.
- Nox GUI process was then **actually restarted**. LAN page displayed
  `Reconnect to 1AC9E666`; clicking it restored seat 2 and the same
  authoritative board/turn.

Screenshot proof is under these host paths (public board only, no private
tokens):

- Glass `/home/brandon/.local/state/stone-and-banner/e2e/lan6-20261105/gui/`:
  `glass-room-lobby.png`, `glass-game-start.png`,
  `glass-first-village.png`, `glass-after-server-restart.png`.
- Nox same path:
  `nox-joined.png`, `nox-game-start.png`,
  `nox-turn.png`, `nox-village.png`,
  `nox-after-server-restart.png`, `nox-after-guest-restart.png`,
  `nox-after-guest-rejoin.png`.

Screen captures were visually inspected: matching 19-hex layout and
positions, legal glow, 1/15 VP for each newly placed village, distinct
host/guest turn labels, preserved board pieces after both restarts.
Initial import-replay misclick, first denied Glass connection during test
firewall setup, and transient form states are retained in adjacent PNGs.

### Clean shutdown

Stopped the Glass test host and both Glass/Nox isolated GUI/Xvfb units.
Verified no TCP/18876 listener and removed precisely the three temporary
nft handles 6, 7 and 8, with no remaining port-18876 rules. Removed only
test-generated private room JSON (which contained recovery tokens).
Screenshot evidence remains. No running LAN service, public endpoint,
device install or production game was changed.

## Boundaries / follow-up

- Live GUI proof covers opening 4 actions, host restart, guest app restart;
  the full 12-step draft plus 3 turns was automated **on Glass loopback
  sockets**, not played to game-over with both cross-machine GUIs.
- No naturally reached 15-VP LAN victory, nonzero rival strategy-card
  secrecy observation from live GUI, or live 20-second/3-minute wait
  with an actual disconnected Linux GUI was claimed. Existing bounded
  reducer/server tests and the wire driver cover these components.
- Crash-safe atomic replacement was verified at process restart, not
  sudden power failure/fsync of the containing directory. The host remains
  a single-process, trusted-LAN-only local service; no public release gate
  is met by this work.
- Production operators should use a private persistent disk path (not tmpfs),
  retain host state through upgrades, never copy tokens to clients, and
  restart on the **same bind address and port**. If the checkpoint fails
  validation, inspect/restore it offline; never delete it to force a room.
