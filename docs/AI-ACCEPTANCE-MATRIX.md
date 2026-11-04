# Stone & Banner — Slice 01/20 AI acceptance matrix

**Date:** 4 November 2026 NZDT. **Baseline:** main at 526ccfc before this slice. **Status:** baseline + acceptance design only; local human-vs-AI is **not implemented** or claimed to work. The current live UI was inspected in Waydroid, not Linux desktop. See evidence/ai_slice01/SCREENSHOT-MANIFEST.md for the per-action record.

## 1. Verified inventory and ownership boundaries

| Area | Current implementation | Consequence for AI work |
| --- | --- | --- |
| Canonical reducer | lib/engine/match.dart: immutable MatchState, sealed MatchEvent, MatchEngine.newGame/apply/replay/exportReplay/importReplay, legal target methods | All AI moves must be MatchEvent instances validated by MatchEngine.apply. No legality or resource mutation in UI/AI controller. |
| Board | lib/engine/board.dart: seeded 19-hex map, 54 vertices/72 edges, terrain and number constraints | AI must evaluate public topology only, with deterministic tie-breaking. |
| Legacy stage-1 model | lib/engine/game.dart: GameEngine, GameState, WindowType and Reaction | Not the live MatchView reducer; do not build AI on this separate early model. |
| Simulation bots | lib/engine/simulation.dart: BalanceBot(track, trade, defend) and BalanceSimulation.run(seats, seed, maxRounds, balance) | Fully automated seeded 3–4-bot balance harness, not a single-seat AI service or human-vs-AI mode. Decisions are coupled to a whole-game loop and full canonical state. |
| Simulation coverage | Setup, dice, Bandit, builds, road, development, some Knights, bank/player trade, Strategy Cards, tactical responses and EndTurn with a bounded action loop (14 action attempts/turn) | Extract reusable *decision* primitives, do not transplant the all-bot while-loop into widgets. The existing heuristic does not prove optimal play or hidden-information fairness. |
| Home and setup | lib/main.dart: Home / Board / Rules NavigationBar; seats segment is 3 or 4, editable names, numeric seed | No human/bot seat selector, no difficulty affordance, no AI label. Core currently rejects two seats. |
| Local session | lib/main.dart: match state, private handoff, replay autosave/resume, event dispatch | AI controller belongs outside the pure reducer and should preserve existing autosave, handoff, import and replay semantics. |
| Board | lib/ui/match_screen.dart: phase-driven canvas, legal target list, actions, tactical panel, trades and replay controls | Must show whose turn it is and when a local AI is deciding, with bounded fallback and no tap race. |
| Strategy hand | lib/ui/strategy_hand.dart: card detail and legal-target sheet | AI must resolve cards via reducer, not simulate taps or reveal rival cards. |
| LAN | lib/network/room_host.dart, room_protocol.dart, lan_client.dart, lib/ui/lan_room_page.dart | Keep existing server-authoritative LAN separate; a local AI match must require zero sockets/server/cloud. LAN snapshot masks rivals' stores/cards and secret seed, useful as a privacy model but not a sufficient deterministic AI seed source. |
| Randomness | Seeded BoardGenerator and MatchEngine.expectedDice/replay events; room IDs/tokens use secure randomness outside game | AI choice must be reproducible from a saved explicit AI seed plus event/decision ordinal, with no clock or ambient Random. |
| Rules/tests | docs/RULES.md; test/ includes 71 existing Flutter tests | Current tests cover hot-seat, simulation, replay, LAN and widgets, **not** mixed human+AI app play. |

**Exact phase and action inventory:** MatchPhase = setupVillage, setupRoad, roll, bandit, actions, invasion, finished. MatchView’s private _Move selection = inspect, village, road, upgrade, bandit, fortify, recruit, activate, promote, knightMove (these are UI selection modes, not reducer events). TacticalKind = bandit, governance, invasion; TacticalChoice = pass, intercept, counter, aid. MatchEvent implementations currently include PlaceVillage, PlaceRoad, UpgradeSite, RollDice, MoveBandit, BankExchange, ProposeTrade, RespondTrade, WithdrawTrade, RespondTactical, TimeoutTactical, DevelopTown, FortifyTown, RecruitKnight, ActivateKnight, PromoteKnight, MoveKnight, ResolveInvasion, PlayStrategyCard, DiscardStrategyCard, EndTurn. Legacy GameEngine has separate WindowType = caravan/invasion and Reaction = offer/escort/blockade; avoid confusing these with canonical tactical events. There is no local AI action or difficulty enum.

**Important incompatibility:** MatchEngine.newGame presently permits only 3–4 players. “Human versus one or more local AI opponents” includes one human + one AI, so exact acceptance requires a carefully tested two-seat rules/setup path, or an explicit product decision rejecting 1v1. Do not silently treat 1 human + 2 AI as proof of 1v1.

## 2. Non-negotiable human-versus-AI acceptance

| ID | Required outcome | Proof required in next implementation slice |
| --- | --- | --- |
| AI-01 | Setup supports at least 1 human + 1 AI and 1 human + 2/3 AI; mixed seats use one canonical MatchState | Reducer two-seat snake draft/turn/round tests, setup widget tests, live 1v1 and 3/4-seat recordings |
| AI-02 | Each AI turn and setup/reaction action is legal; no free resources, VP or turn skipping | Property tests over many seeds: MatchEngine.apply never rejects AI output; bank + escrow conservation and replay identity after every action |
| AI-03 | No reading hidden opponents' resource quantities/cards or secret future events | A decision-view DTO containing public state + own hand only; adversarial tests vary rivals' hidden hands while public view is held fixed and verify identical choices where no legal public signal changes |
| AI-04 | Same board seed, AI seed, seat definitions and initial events produce identical event stream, result and restored game | Byte-identical exported event log across repeated runs, app restart and import/replay |
| AI-05 | AI works offline with no server, cloud, account, proprietary SDK, model download or network permission dependency | Disable network in isolated Linux and Waydroid tests; play setup through AI response and verify no socket/API activity |
| AI-06 | Human sees which seat is AI, an obvious AI-turn indicator, and a clear next-human handoff, without exposing private hands | Widget + device screenshots for pending/acting/completed states, screen reader labels, human input disabled only while AI owns action |
| AI-07 | Every AI decision is bounded and can be safely skipped/timed out without deadlock, duplicate action or replay divergence | Fault-injected policy throwing, producing illegal/stale action, or exceeding a step/time budget; reducer-safe fallback by phase with deterministic logged event |
| AI-08 | No wall-clock timing or UI animation affects game outcome; pauses/cancellations cannot produce double dispatch | Replay and rapid background/resume tests; exactly-once serialized event dispatch |
| AI-09 | AI handles legal tactical response, standing offer recipient, Bandit, Invasion and victory without “pass device” pretending to be a human | Scripted fixtures for each response and bounded fallback; UI only hands off to human seats |
| AI-10 | Difficulty selector appears only if two policies have empirically different legal decisions/strength across independent seeds | If only one policy exists, omit difficulty control; if two, predefine metrics and test meaningful differences |
| AI-11 | Existing offline hot-seat, private saved replays, LAN rooms and seeded balance harness remain working | Existing 71-test suite + new tests + local smoke for all modes |
| AI-12 | Material 3 UI stays minimal with progressive disclosure, legible type/contrast and sparse actions; no new controls in every turn phase | Per-action timestamped screenshot manifest on actual Linux and Waydroid apps, with expected/actual/visual verdict and repairs re-shot |

### Deterministic fallback contract (proposed, not implemented)

- Bound deliberation by **count of proposed events/decision steps**, not a timer inside MatchState. The UI may have an external safety timer, but the outcome must be a deterministic, replayed action.
- Setup Village/Road: choose the lowest stable-index legal target from MatchEngine legal target collections when policy fails; never invent geometry.
- Roll: submit only MatchEngine.expectedDice(state); never roll a fresh random number.
- Bandit: select a deterministic legal hex, and victim only from MatchEngine.banditVictims. Tactical responder: Pass or TimeoutTactical with the exact window ID/responder.
- Invasion: ResolveInvasion when legal. Action phase: EndTurn if no safe move. Finished: dispatch nothing.
- Validate each proposed move with MatchEngine.apply on the authoritative state; serialize one event at a time and persist it before scheduling the next. Cap repeated rejected proposals and retain the failure reason.

## 3. UI screen / overlay coverage matrix

Legend: **Observed** = opened and screenshot inspected on a real Waydroid instance in this slice; **Existing test** = code test found and/or executed in full suite, not a claim of device E2E; **Planned** = must be exercised later. All Linux desktop UI interactions are **planned, not executed**.

| Screen/interaction | Current baseline and source | AI acceptance or regression | Evidence status |
| --- | --- | --- | --- |
| Home / welcome | Crest, short promise, 3–4 seat setup; main.dart | Local vs AI mode and bot seat choices kept concise; offline cue | **Observed** 02 and 12 |
| New local match setup | Names, numeric seed, Start, 3/4 segment | Per-seat Human / Local AI, minimum 1 human, 1v1 support, bot names, no fake difficulty | **Observed** 02, 05; AI absent |
| Board before match | Centered Create a match | Empty-state CTA routes to setup | **Observed** 04 |
| Rules | Founding rules scroll view, main.dart | Separate AI turn explanation; preserve readable rules | **Observed** 03 |
| Private human handoff | Full-screen lock / “I’m ready” | Only for humans; no AI hidden hand flashing | **Observed** 06, 10, 13 |
| Setup Village board | Glowing legal junctions, score, resource chips | AI legal placement automatically advances; human canvas/list kept | **Observed** 07, 11, 14 |
| Setup Road board | Glowing legal sides | AI free road placement, then correct snake next seat | **Observed** 09 and 10 action |
| Legal-target bottom sheet | Scrollable junction/road/Bandit labels | Preserve accessibility, perhaps progressive filtering for long lists | **Observed** 08 |
| Roll phase | Roll dice button and score | AI seeded roll, no wait for absent player | **Planned** (existing widget tests only) |
| Bandit hex/victim dialog | Canvas/list target and optional victim dialog | Legal target/victim, interception response, no hidden hand query | **Planned** |
| Tactical Bandit response | Intercept, Pass, Skip/timeout | Auto-response by bot; exact window/seat, bounded | **Planned** |
| Tactical Governance response | Counter card, Pass/timeout | Auto-response if legal, privacy safe | **Planned** |
| Tactical Invasion response | Ore/wheat aid, Pass/timeout; resolve panel | AI aid/pass and resolve, no stall | **Planned** |
| Action board tools | Inspect, Road, Village, Upgrade; Knights/Fortify/Develop | Human controls remain; bot moves displayed as distinct, short events | **Planned** |
| Bank exchange dialog | Resource selectors/rate/quantity | AI can bank trade legally, rate/stock conserved | **Planned** |
| Player trade dialog | Target, give/want, count and counter | AI offer/accept/decline, no omniscient acceptance | **Planned** |
| Incoming offer strip | Accept, Decline, Counter, Withdraw | AI-owned offers handled automatically; humans retain agency | **Planned** |
| Strategy hand & card detail | Track cards, legal option sheet, discard | Bot plays/discards only held cards; no rival card leak | **Planned** |
| Victory banner | 15 VP banner, finished phase | AI win/lose clear; no further dispatch, replay intact | **Planned** |
| Replay copy/import | Compact and JSON copy, import dialog | AI seed/policy configuration durable in replay metadata; warn full private export | **Planned** |
| Saved match resume | Continue button, private handoff | AI resumes from event ordinal exactly once, no auto-run double dispatch | **Observed** 12–14 |
| Validation/snackbars | Invalid seed/name/replay, illegal move | Friendly errors without broken board or AI loop | **Planned** |
| LAN room setup | Server URL, Create/Join, seat count, name/seed | Preserve separate flow; AI not dependent on LAN | **Inspected code; UI not opened** |
| LAN lobby | Seat list, invite code, creator start | No regression in authoritative room | **Inspected code; UI not opened** |
| LAN active board/reconnect | Server view, waiting indicator, recovery token | Existing LAN privacy/timeouts unchanged | **Existing tests; UI not opened** |

**Visual review of observed landscape screens:** cohesive dark Material 3 palette, contrast and rounded controls were acceptable. Wide display has a narrow central content column and comparatively small action copy; legal target sheet is long and ungrouped. These are recorded UX follow-ups, not claims of automated accessibility certification. No UI code changed in this baseline slice.

## 4. Rules and reducer coverage matrix

| Feature / event group | Existing engine/test anchor | Local AI acceptance scenario | Slice 01 status |
| --- | --- | --- | --- |
| Board seed, terrain, 19 hexes and 6/8 constraints | board.dart; board_test.dart | Same seed, same public map; AI sees no future rolls | Existing tests, AI untested |
| 54 vertices, 72 edges, legal adjacency | MatchEngine.legalVertices/Edges; match_test.dart | No adjacent villages, road through enemy or invalid index | Existing tests, AI untested |
| 2–4 seat snake setup and starting goods | MatchPhase.setupVillage/setupRoad; match_test.dart | 1v1 2-seat extension plus existing 3/4 snake; auto bot placement | **2 seats unsupported**; 3/4 tested |
| Dice and production / finite bank | RollDice, MatchEngine.expectedDice; match_test.dart | Seeded roll, exact stock transfer, empty bank no minting | Existing tests, AI untested |
| Seven discard and Bandit theft | MoveBandit, banditVictims, protected capacity; advanced_test.dart | Legal victim, seeded theft, hidden hands untouched by policy | Existing tests, AI untested |
| Road network / longest-road bonus | PlaceRoad, longestRoad; match_test.dart | Legal road and 5+ trail scoring/tie retention | Existing tests, AI untested |
| Villages, Towns, Capitals, 15 VP | PlaceVillage, UpgradeSite, winner; engine/match tests | Bot builds only affordable legal targets; terminal victory stops | Existing tests, AI untested |
| Seasons and round boundary | EndTurn, Season, round rotation; engine_test.dart | AI EndTurn progresses seasons/replenishes reactions | Existing tests, AI untested |
| Reaver pressure / Invasion | ResolveInvasion, defenceStrength, invasionStrength; advanced_test.dart | Bot resolves pressure without spin or fabricated aid | Existing tests, AI untested |
| Knight recruit/activate/promote/move/displace | RecruitKnight/ActivateKnight/PromoteKnight/MoveKnight; advanced_test.dart | AI selects legal target and pays costs; optional policy may pass | Existing tests, AI untested |
| Fortification / raid prevention | FortifyTown and invasion damage; advanced_test.dart | AI uses only legal Town/Capital defence | Existing tests, AI untested |
| Five Town Development tiers on three tracks | DevelopTown; advanced_test.dart | Bot focus optional but cost/benefit deterministic | Existing tests, AI untested |
| Development commodity conversion | Paper/cloth/coin stock; advanced_test.dart | No extra resources or double conversion | Existing tests, AI untested |
| Bank trade 4:1 / Commerce 3:1 and 2:1 | BankExchange, tradeRate; match/advanced tests | AI tests actual bank stock and received quantity | Existing tests, AI untested |
| Catch-up 3:1 once/round | MatchBalance, catchupUsed; engine/balance tests | Bot may use without spawning goods or free VP | Existing tests, AI untested |
| Bounded dry-roll relief | dryRolls, reliefUsed; advanced_test.dart | AI events must not circumvent relief cap | Existing tests, AI untested |
| Standing escrow trade | ProposeTrade, RespondTrade, WithdrawTrade; stage5_reactions_test.dart | Bot proposes, accepts/declines only on own seat; one counter max | Existing tests, AI untested |
| Offer expiration/refund | MatchEvent reducer; stage5_reactions_test.dart | AI timeout/turn advancement refunds exactly once | Existing tests, AI untested |
| Bandit Knight interception | TacticalKind.bandit, RespondTactical; stage5_reactions_test.dart | Bot intercepts only with active Knight and token | Existing tests, AI untested |
| Governance card counter | TacticalKind.governance, counterCards; stage5_reactions_test.dart | Bot responds using own matching held card | Existing tests, AI untested |
| Invasion aid clockwise | TacticalKind.invasion, RespondTactical; stage5_reactions_test.dart | Bot pledged wheat/ore only if held; finite response queue | Existing tests, AI untested |
| Explicit tactical timeout | TimeoutTactical(window ID, player); stage5/6 tests | No stale or duplicate response; fallback cannot deadlock | Existing tests, AI untested |
| Three 18-card strategy decks | cards.dart; strategy_cards_test.dart | Bot can assess available own cards, no private peek | Existing tests, AI untested |
| Legal card targets, discard, hand cap | legalCardPlays, PlayStrategyCard, DiscardStrategyCard; strategy_cards_test.dart | Bot picks one legal card action or safely passes/discards | Existing tests, AI untested |
| Winner/terminal legality | MatchPhase.finished, MatchEngine.winner; match_test.dart | End immediately at 15 VP, no extra AI event | Existing tests, AI untested |
| Export/import/replay byte identity | MatchEngine.replay/exportReplay/importReplay; many tests | Same bot decisions after restart, seed and ordinal preserved | Existing tests; AI metadata absent |
| Hot-seat hidden hand / autosave | main.dart; release_hardening_test.dart | Human/AI transitions never leak hands; resume correct seat | **Observed hot-seat only** |
| LAN filtered per-seat view | RoomProtocol.view; stage6_room_test.dart | No regression; AI must not request raw canonical secret data | Existing tests; LAN UI not opened |
| LAN host timeout/dedupe | HostedRoom; stage6_room_test.dart | Local AI remains independent; no server and no duplicate callbacks | Existing tests; no live LAN |

**Test granularity:** Existing tests validate reducer rules. This matrix does not convert their assertions into “AI accepted” or into unseen device interactions. No human-versus-bot scenario has run yet.

## 5. Device interaction sequences for acceptance

### Waydroid x86_64 — executed baseline

- Installed the pre-existing release APK (SHA-256 360ab294347987cd7011e40a1d1365b8663aa7bde564aaac590e6ef2075166d2).
- First launcher-monkey attempt failed (exit 251); screenshot deliberately records Android launcher. Explicit MainActivity start succeeded.
- Opened Home → Rules → Board empty → Create a match → Start three-player match → Player 1 private handoff → board.
- Opened legal-target sheet; chose Junction 1; observed 1/15 VP and setupRoad; tapped legal Road; observed private Player 2 handoff; unlocked next board.
- Rebuilt release with JDK 17 override (buildq #4716), reinstalled in same Waydroid; Home showed Continue saved match; resuming showed Player 2 private handoff and then board with earlier village/road intact.
- Every performed navigation/tap has a timestamped PNG, expected/actual/visual verdict in evidence/ai_slice01/SCREENSHOT-MANIFEST.md. No claim of a complete match or AI opponent.

### Linux desktop — **planned, not executed**

1. Launch actual Linux Flutter app in isolated test process; screenshot Home after navigation, assess large-window typography/layout.
2. Choose one human / one local bot with reproducible seed; screenshot each setup selection and bot badge.
3. Start; screenshot first human handoff/board; perform one legal Village and Road, screenshot immediately after each.
4. Observe AI's setup village/road with AI-turn indicator, screenshot before/after each bot event; verify no human prompt for bot.
5. Finish snake draft, roll, make a build/trade/end turn and observe next AI turn; screenshot every action.
6. Use a seeded Bandit/reaction and Invasion fixture; screenshot panel, AI response, resolved state.
7. Background/restart mid-AI decision; screenshot resume and ensure same replay, no duplicates.
8. Disable network, repeat an AI event; verify no socket/API dependency. Export/import and compare event log.

### Waydroid — **planned AI acceptance, not executed**

1. Build release from current sources with validated JDK; install only on isolated Waydroid, screenshot launch.
2. Select 1 human + 1 AI (or record 2-seat blocker), set explicit seed; screenshot each choice.
3. Start, unlock human handoff; place legal Village/Road; screenshot each action.
4. Screenshot AI-turn indicator, first autonomous legal Village/Road and next human handoff; capture expected/actual.
5. Repeat 3–4-seat mixed setup, deterministic dice, bank/player trade, cards and tactical timeouts.
6. Force-stop and relaunch during AI turn; screenshot saved-state/turn result; prove byte-identical event stream.
7. Test offline mode without touching the Samsung device. Record orientation, font scaling and accessibility gaps honestly.

### Per-action screenshot contract

For **every** screen opened and meaningful interaction: perform action → allow only minimal UI settling → capture timestamped PNG from actual app → append manifest row with action, expected, actual and visual verdict → visually inspect typography, spacing, state, contrast, hierarchy, sparse controls. If safe UI correction follows, retake the same screen with a new timestamp and note before/after. Automated goldens are supplementary, not device screenshots.

## 6. Stage 2 handoff: implementation boundaries

- Add a seat-kind model (human / local AI) and serialized AI policy/seed to local match metadata without changing deterministic reducer semantics or leaking private replay data. Plan explicit backward-compatible import of old replays.
- Extract a pure seat-scoped policy from BalanceSimulation rather than exposing MatchState or using its whole-game all-bot loop. Input: public board/phase/score/bank, own hand, legal categories/targets, own policy, saved seed and ordinal. Output: at most one proposed MatchEvent or a bounded no-op reason.
- Keep MatchEngine.apply the only authoritative mutation path; let reducer revalidate. Preserve the existing Dice, Bandit, tactical window, bank and hidden-hand rules.
- Add a serialized local controller for AI actions that persists each accepted event, renders a short AI-turn indicator, and auto-handoffs only when the next seat is human. Do not run AI while screen is on Home/Rules or after disposal without an explicit state machine.
- Cover 2-seat snake draft implications (current MatchEngine rejects two seats), plus 3/4-seat order, timeout fallback, invalid proposed moves and exactly-once app resume.
- Keep LAN classes and hot-seat routes intact; no network, cloud, paid AI, Riverpod, go_router or public store release.
