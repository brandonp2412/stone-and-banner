# Stone & Banner — original rules (working specification)

## Objective and map

3–4 local seats in Stage 2. First player to **15 earned Victory Points** wins. Village = 1 point, Town = 2 total, Capital = 4 total (upgrades replace rather than stack). Guardian's Honour and Charter Points count separately when earned. A board has 19 axial-coordinate hexes, with four Woodland, three Clay Beds, four Fields, four Meadows, three Ridges and one Barren tile. Exactly one Barren has no number. Number bag: 2 and 12 once, 3/4/5/6/8/9/10/11 twice. Adjacent 6/8 tokens and same-terrain three-way vertices are forbidden. Save the explicit seed and resulting layout in each match replay.

## Goods and phases

Wood, brick, wheat, wool and ore support construction. Town developments produce paper, cloth and coin. Dice, seasonal supply and event outcomes become explicit events. Local setup uses a fair 2–4-player draft. Each confirmed action validates construction costs, geometry and ownership; no goods can be minted by undo, reconnect or repeated events. Stage 2 costs: Road = wood + brick; Village = wood + brick + wheat + wool; Town (replacing Village) = 2 wheat + 3 ore; Capital (replacing Town) = 2 wheat + 2 ore + one each of paper, cloth and coin. The first Capital earns one Charter Point; later Capitals gain only their structure value. A snake draft places two free Village/Road pairs per player; the second Village receives one basic good per adjacent productive tile. Play turns require one deterministic dice roll, Bandit movement on seven, then zero or more construction/trade actions and End Turn. Villages cannot neighbour other settlements and must join the owner’s roads outside setup. Roads cannot continue through enemy settlements. Longest uninterrupted trail of at least five road sides earns 2 VP (ties retain the incumbent).

## Seasons, common defence and recovery

Seasons rotate Thaw → Bloom → Harvest → Frost every three full rounds. Reaver pressure increments at each completed round. Reaver Fleet invasions challenge shared defence; Knight, escort, and loss outcomes must be deterministic and previewable. A trailing seat three or more points behind the leader may use one **3:1** bank exchange per round, instead of the usual **4:1**; this consumes actual resources and grants no free Victory Points. Reset that allowance at the next full round. Additional anti-runaway effects must never introduce infinite loops.

## Strategy and reactions

Three distinct decks: green **Innovation** (infrastructure), yellow **Commerce** (trade), blue **Governance** (tactics and defence). Their usefulness must be simulation-tested; equal card counts alone are not proof of balance. Two bounded reaction windows begin with Caravan and Invasion. Eligible nonacting players may spend reaction tokens on Offer, Escort or Blockade where legal; Caravan disallows Blockade and Invasion disallows Offer in the Stage 1 engine. Each seat starts with one reaction token per round. Record response order, passes and expiration explicitly; never stall a disconnected multiplayer match indefinitely.

Matches remain local, with finite bank stock (19 of each good), reproducible roll and theft randomness, replay import/export, and explicit trade acceptance. Strategy Cards arrive in Stage 4.

## Stage 3 rules

The five named Town Developments per track appear in the glossary. A player needs at least one Town to develop. Tier I costs 1 wheat + 1 ore; II–V each cost 1 wheat + 2 ore + (tier minus 1) of the matching commodity. At Towns and Capitals, Innovation converts one Woodland yield into paper, Commerce one Meadows yield into cloth, Governance one Ridges yield into coin; tier V converts two. Conversion replaces basic yield and respects finite bank stock.

Innovation II Stoneworks discounts Roads to one wood. III Aqueduct reduces dry-roll relief threshold to two; IV Supply Network changes which good that single relief grants; V Observatory adds 1 shared defence. Commerce II Market Hall gives 3:1 bank trades; III Trade Wharf doubles cloth receipts (stock permitting) and protects two hand goods; IV Guild Exchange gives 2:1; V Grand Bazaar grants two goods per bank trade (without stacking with the Wharf). Governance II Watchtower adds 1 shared defence; III Fortifications adds two protected hand capacity and negates Invasion hand raids; IV Marshal's Hall discounts Knight recruitment; V High Council adds another shared defence.

Each seat may recruit up to three Knights at its road junctions: an inactive Sentinel (1 wool + 1 ore), later activated (1 wheat), promoted to Warden (1 ore + 1 wool), then Champion (2 ore + 1 coin). Active ranks contribute 1/2/3 shared defence. Each Knight acts at most once in a turn. It can move one of its roads, displacing a weaker Knight; the displaced piece retreats to the lowest-index available junction on its own road, or leaves the board. A Fortification on a Town/Capital costs 2 brick + 1 coin, adds one defence and two hand capacity, and absorbs one failed Invasion hit. On a seven, hands above their protected capacity (base 7) discard half to the bank deterministically.

Reaver pressure advances on sevens and completed rounds. At pressure 3 or greater, an Invasion pauses play at the next round boundary. Threat is 4 + prior Invasions + excess pressure. Successful collective defence earns one Guardian's Honour VP only for a unique player with the strongest active Knight contribution. Failure destroys one Fortification or downgrades the highest-scoring Town/Capital and raids up to two hand goods, unless protected by Governance III. A Town reduced to Village has a one-use discounted rebuild (1 wheat + 2 ore).

Drought relief only applies to seats behind by at least 3 VP after three dry production rolls, and at most once per three-round season. Aqueduct lowers this to two rolls; Supply Network selects a least-held available basic good instead of wheat. These enhancements never add two payouts for one roll, never give VP, and transfer the good from the bank. The original once-per-round 3:1 catch-up trade does not stack with improved Commerce trade rates.

## Stage 4 — Strategy Cards

Innovation (green), Commerce (yellow), and Governance (blue) each have 18 original physical cards, with duplicates. The exact names, quantities, effects and descriptions live in `lib/engine/cards.dart`. All players use the same decks. When the two numbered dice are rolled, an independent seeded event face 1/2/3 offers the corresponding strategy track; 4/5/6 offers no card. A seeded tier check from 1–5 must not exceed the receiving player's Town Development level in that track. All qualified players draw in roller-first seat order. Four cards maximum per hand; full hands skip draws. Physical cards go to discard after play or voluntary discard and reshuffle deterministically when required.

Card plays occur in the owner's action phase, after the Bandit is resolved and with no pending offer. An explicit target or resource choice is validated by the pure reducer, as are bank stock, road/fortification geometry, Knight eligibility and enemy-owned resources. Effects cannot create goods: resources move between player stores and finite bank or between player stores. Unplayable cards may remain in hand or be discarded; they never prevent ending a turn. Each action records a replay event. Public draw reports expose counts, never private card identities.

See `docs/STAGE4_BALANCE.md` for sampling targets, measured event rates, limits, and unresolved match-equity deviations.


## Stage 5 — Standing offers and out-of-turn responses

**Standing trade.** During their action phase, a player may post one outstanding
offer to another seat using positive quantities of two different goods. Offered
goods leave spendable stores for escrow, and remain in finite supply totals.
Terms are public, but the recipient's hand contents are not. Posting does not
pause a turn or spend a reaction allowance. Only the recipient may accept or
decline, during their own action phase. Acceptance transfers escrow exactly
once and the requested available goods to the proposer; if insufficient,
acceptance is disabled and decline remains legal. Decline and withdrawal
return escrow. An offer expires/refunds as its proposer next becomes active,
after every other seat had a turn. Only one offer per proposer is live. A
recipient may counter once during their action phase, atomically refunding
and replacing original escrow, reversing roles and setting a counter flag.
A counter cannot itself be countered.

**Tactical window.** A qualifying event is recorded before its effect settles.
The acting seat cannot move during the response. Each window carries an
event-ordinal ID and a deterministic respondent queue. Every response and
timeout must match both ID and first responder; stale or duplicate actions
fail. Pass/timeout never spends allowance. A seat has **one successful
tactical response per round**; reset at the next completed round. Posting,
accepting, declining or countering a standing trade, ordinary turn actions
and passing do not consume it. Counter-responses cannot recurse.

- **Bandit:** After a victim is chosen and before seeded theft, that victim
  may intercept using any active Knight if the allowance remains. The
  lowest-index active Knight is exhausted; the Bandit moves without theft.
  Pass/timeout makes the one original seeded theft.
- **Governance:** A targeted Political Pressure or Supply Raid can be
  canceled by a held Boundary Dispute; targeted Defection by held Defection.
  Attacker and counter cards are each discarded once; nothing transfers.
  Pass/timeout applies the original validated effect once. Other plays
  settle immediately.
- **Invasion:** At the round boundary, before resolution, eligible nonacting
  seats with wheat or ore respond clockwise after the new active seat.
  Each may spend exactly one wheat (+1 temporary defence) or ore (+2)
  to the bank; or pass. Aid does not count toward Knight Honour. After
  the last response, the active seat resolves; temporary aid resets.

Local pass-and-play uses private handoff, immediate Pass and visible
Skip/timeout fallback without mandatory waiting. A future authoritative
network session can schedule TimeoutTactical events; device wall clocks
do not enter game state or replay. All ordering and expiry is event-derived.

## Stage 7 — measured balance, no production rule change

All Stage 3–5 numerical rules above remain the release defaults. The
deterministic simulation harness measures seeded legal bot games and compares
replay-stored alternative rule parameters without enabling those alternatives
in hot-seat or LAN sessions. A 360-game baseline found no clear first-seat
or green runaway, but Commerce-focused bots won more often than Innovation.
The tested recovery and Commerce variations did not consistently improve
that gap in independent seeds; see `BALANCE.md`. A trailing seat can still
trade 3:1 at most once per round, with real bank goods; drought relief is
once per three-round season, behind by 3 VP, and never awards free points.
These conclusions are bot-model-dependent, not proof of human match parity.
