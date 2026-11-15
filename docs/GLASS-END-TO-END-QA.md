# Glass and Android end-to-end QA — 15 November 2026

Baseline: `98aeeb7`, on `main`. This pass follows the landscape overhaul in
[LANDSCAPE-REDESIGN.md](LANDSCAPE-REDESIGN.md). No rules or game randomness were
changed. No physical phone, public host, or unrelated machine was used.

## Fixes from the pass

- A waiting LAN client's inventory showed the active rival's filtered zero
  counts. It now displays the viewing seat's actual private inventory.
- The LAN waiting overlay covered standings and left a disabled “Roll dice”
  prompt describing the rival's turn. Waiting now occupies the side panel,
  preserves standings and the map, and exposes no action controls.
- An additional LAN app bar consumed scarce landscape height. During play,
  the leave control now uses the reserved space beside the standings.
- A real Android 640×320 / 1.6× text check exposed clipped standings,
  instructions and inventory. Heights now use the individually scaled font
  sizes, including padding and borders. A nonlinear-scaler regression first
  reproduced the failure and now passes; the rebuilt APK was visually checked.
- Compact four-seat standings now fit all four scores; a minimum card width
  of 148 clipped the fourth score at 640 logical pixels. The final width is
  128, with a regression and Android before/after captures. Long names and
  realm labels truncate at large text; scores remain visible.
- Finished standings say “Winner” instead of “Taking a turn”.
- Terrain labels now say “Clay Beds”, rather than `clayBeds`. Card targets
  use the same one-based junction, road and hex numbers as board target lists.

## Actual UI coverage

Glass Desktop's installed proxy was inspected after its underlying diagnostic
incorrectly suggested shared input only. The proxy routes input through the
private compositor background socket. The successful test interactions record
unchanged cursor and keyboard/pointer focus observations.

A temporary Linux host compiled the actual Flutter sources. Its test app ID,
window title and data directory were isolated from the normal app. After an
initial launch took focus and was immediately closed, subsequent testing used
a separate headless dwl session. Only that disposable session needed a keyboard
capability configured for GTK; the shared compositor was not restarted or
modified. Input and screenshots used the installed Glass MCP bridge's
`screenshot`, `click`, `scroll`, `press_key` and `type_text` tools over MCP.

The Linux host's AI correctly pauses when unfocused. Active AI progression
was therefore checked separately in the dedicated Android emulator, not
bypassed in the Flutter app. Android commands always selected
`emulator-5580` and checked `ro.kernel.qemu=1`.

| Area | Observed live |
| --- | --- |
| Home and setup | Landscape Home; hot-seat/AI selection; four seats and three computers; names/seed expansion; invalid numeric seed rejected; three-seat solo-human Android setup |
| Map and placement | Free Village and Road through target lists and map hits; legal target marks; probability pips; dice and production outlines; zoom and reset; fixed map while action panel scrolls |
| Privacy | Private handoffs after resume, trades and responses; public board and concealed goods during AI and tactical windows |
| Construction | Town upgrade with exact wheat/ore cost and score change; Capital upgrade taking 12 to 15 VP; controls disabled after victory |
| Development | Innovation tier purchase, paid goods removed and unaffordable next choices disabled |
| Bank | 4 wool for 1 wood; 3 ore for 1 wool; 2 brick for 1 wool; displayed rates, stock and affordability; unaffordable quantity disabled |
| Standing trades | Compose and escrow; end turn and recipient roll; accept; counter with reversed terms; decline; withdraw and refund; no duplicate offer left after completion |
| Cards | Founding Charter detail, explicit effect selection, confirm, hand 1→0, brick 0→1 and coin 1→2 |
| Defence | Wheat pledge increments defence; handoff back to actor; Invasion preview and resolve; Knight interception prevents theft and exhausts the piece |
| Replay | Invalid code gives a friendly error without echoing private input; valid compact code typed through MCP; replacement warning, import and private unlock; saved-match recovery |
| Rules | Essentials, advanced rules and glossary remain scrollable in compact landscape |
| LAN | Real loopback WebSocket host, GUI room creation, two scripted peer clients, lobby/start, snake setup, authoritative roll, rival turns, filtered private inventory, client restart/reconnect, compact play and leave control |
| Android full game | See the full-game result and replay audit below |

Linux captures include both a large viewport and an 853×454 window surface
with GTK decoration, leaving approximately 813×368 for Flutter. The final
compact LAN capture shows the restored board space without a second app bar.
Android uses the release APK, with landscape and immersive presentation.

## Validation

Final application source: clean `flutter analyze` (Pueue 6021),
**224 passing Flutter tests** (6022), release APK build (6023), and
Linux inspection build (6017). The normal-size board golden was inspected
and refreshed for intentional instruction/tray line-height changes (6018).
No other golden changed.

## Automated coverage supporting the UI pass

- All 28 original card designs go through their selection/confirmation UI at
  640×320 normal text and 844×390 with 1.6× text. All **56 cases** pay/transfer
  through `MatchEngine.apply`, consume a physical card, preserve all goods and
  card copies, and reproduce the same reduced state. Geometry labels are
  checked against one-based board numbering.
- Fortify, recruit, activate, promote and two-step Knight movement are each
  selected through the tabletop and legal target sheet at both text sizes.
- Governance counter, pass and timeout are tested at both text sizes, including
  concealed hands, exact rival goods and both attack/counter card accounting.
- A LAN regression test supplies a filtered rival-turn view: the active rival
  has zero visible wood, while the viewing seat's tray correctly shows seven.
  Waiting has no “End turn” or “Computer turn” control.
- Existing tests cover seeded topology, setup, production, empty bank, seven
  discards, theft, road scoring/ties, all development tiers, Knight displacement,
  raid/fortification outcomes, reactions and stale responses, trade expiry,
  escrow/refunds, decks/draw/reshuffle/hand cap, persistence errors, AI privacy
  and cancellation, LAN authority/deduplication and terminal legality.
- A separate 80-game deterministic corpus (seeds 9200–9219, three/four seats,
  all heuristic and simulated-human cohorts) had **zero failures**. Seventy-seven
  finished; three simulated-human games reached the 90-round cap. This is
  reducer/policy evidence, not 80 observed device games or a balance claim.
- A real three-socket LAN smoke run passed authority, deduplication, fan-out,
  filtered state and reconnect checks.

## Full-game result and replay audit

Final results are recorded in `evidence/glass-qa-20261115/results.json`.
The first Android run starts from the actual setup controls, with seed 20261027,
Player 1 and two computer opponents. The scripted human selects legal setup
positions, rolls, moves the Bandit without taking goods, passes responses and
ends turns. The two AI seats play autonomously. This is a deliberately passive
human path, not a claim of representative strategy quality.

It completed **round 80, 1,003 events, scores 2 / 15 / 12**, with Computer 1
winning. This first game ran on the earlier candidate (Pueue build 5985);
its APK hash was not retained before replacement. Its final state was then
restored on the final release APK.

A second, **offline four-seat game** (seed 4, one human and three AI) reached
**round 20, 370 events, scores 2 / 2 / 8 / 15**, with Computer 3 winning.
It ran on build 6016, SHA-256
`3dbe933850f5903872f13dc7034999a182053d6d28e2f836db7b0c8ff92d992f`.
All 371 states passed the replay audit. The final build 6023 changes only the
standings minimum width relative to this game; the saved victory was restored
and inspected at normal and 1.6× Android system text. A complete game on build
6023 is not claimed. Final APK SHA-256:
`946afbe9f471802fbcb32a670f52e07623a083a9cfd501e3e3307d4b26d3cca3`.

A force-stop/relaunch at event 82 preserved the exact session and replay bytes
before continuing. The final replay must retain all 82 earlier events unchanged.
The audit passed for all **1,004 states**, including the initial state.
The entire saved history is reduced again from its original seed; every
intermediate state's bank, hands, escrow and each physical strategy card copy
are checked. Canonical export/import bytes must also remain identical.

Reproduce an audit using:

```sh
dart run tool/verify_replay.dart FINAL_REPLAY.json EARLIER_REPLAY.json
```

## Evidence and limits

Curated, inspected screenshots and results are in
[evidence/glass-qa-20261115](evidence/glass-qa-20261115).
The complete per-action screenshots, MCP records, Android UI-node records,
replays, helper scripts and validation logs are retained locally at:

`/home/brandon/.local/state/stone-and-banner/e2e/glass-qa-20261115/`

Rare actions use genuine accepted-event checkpoints; these are explicitly
separate from the Android game played from setup. All 28 card designs and
all development/rule branches are covered by widget/reducer tests; this does
not claim each was individually played on a physical phone.

One historical Slice 13 bank-2-to-1 fixture is rejected at event index 311:
Resource Levy requests brick when the bank has no brick. The UI safely rejects
that saved history. The original fixture was retained; a new current-engine
checkpoint was generated and audited before the successful live 2:1 exchange.
This pass does not make a blanket compatibility claim for all historical
pre-release replay files.

Harness failures were retained: missing headless keyboard capability, an
oversized native typing burst, initial Python element truthiness, and an adb
root reconnection interruption. Short typing chunks and bounded adb retries
were used afterward. New widget harnesses initially waited for an endless
progress animation or selected the underlying expansion tile rather than the
modal target list; these were corrected before final validation. These failed
attempts are not counted as successful gameplay checks.

Automated tests, screenshots, deterministic replay audits and emulator play
complement each other. This report makes no physical-device, network-latency,
formal accessibility certification, store-release or equal-strength balance
claim.
