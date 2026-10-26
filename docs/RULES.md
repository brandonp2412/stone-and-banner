# Stone & Banner — original rules proposal v0.1

**Status:** Complete *proposed* table rules for implementation/playtest, not yet a verified balanced game. All numbers below are design constants pending simulation. No rules text, artwork or branding borrowed from another game.

## Aim, inventory and play space

2–4 players build a frontier economy, construct towns, defend the realm from Reavers and complete public deliveries. First to **15 Victory Points** on their own turn wins after any already-open reactions resolve. If more than one player qualifies on the same resolution, the current player wins only if qualified, otherwise highest score then seat order. No points are awarded solely for being behind.

Board: **19 connected land hexes** in a radius-2 hexagon, each with a number 2–12 except 7. Terrain inventory: 4 woodland (wood), 3 clay beds (brick), 4 fields (wheat), 4 meadows (wool), 3 ridges (ore), 1 barren (nothing). Shuffle terrain subject to no three matching terrains sharing a vertex. Assign production numbers from this exact multiset: 2×1, 3×2, 4×2, 5×2, 6×2, 8×2, 9×2, 10×2, 11×2, 12×1, plus no number on barren. No two 6/8-numbered tiles may share an edge. Put 3 neutral district markets on alternating board-edge vertices; all coast-edge links are potential ports. Save the initial seed, tile order, number order, markets, and seat order for replay.

Pieces: roads on hex edges, Villages/Towns/Capitals on hex vertices, knights stationed at a friendly holding or adjacent road, a Reaver Fleet pressure dial (0–4), one Bandit road marker, Caravans, development trackers, the bank and three Strategy Card decks.

Each player may control at most **six occupied vertices**, at most **one Capital**, up to **three knights**, a hand of **three Strategy Cards**, and up to **two Guardian's Honour VP** and **two contract/Charter VP**. Resources in the bank are unlimited (app implementation). Basic goods: **wood, brick, wheat, wool, ore**. Crafted goods: **paper, cloth, coin**. All goods are visible counts except the contents of a player's Strategy Card hand.

## Setup

Randomise seating from a saved seed or let players choose it. In forward order, then reverse order, each player places one free Village and one road incident to it, for two Villages and two roads. New Villages must not be immediately adjacent along one board edge to any other occupied vertex. A road may not overlap or pass through a rival's occupied vertex. For the second Village, take one basic resource from each adjacent producing hex. Every player starts with **2 VP** and one unready knight (with no strength until readied), no crafted goods, no Strategy Cards. Set season Thaw, round 1, pressure 0.

## Rounds, seasons, production, actions

A **round** is one turn for every seat, clockwise. On your turn:

1. **Forecast:** reveal public current season, district demand and Reaver Pressure. Optionally spend a Forecast card.
2. **Production:** roll two fair six-sided dice once. All Villages touching a numbered hex matching the sum receive one matching basic good; Towns receive two; a Capital receives three. Barren hexes produce nothing. **7** triggers a Market Shift instead: rotate active district demand clockwise, move the Bandit to any unguarded road, then each player with more than seven basic goods discards two of their choice. Bandit never prevents resource production.
3. **Two actions:** spend up to two Action Points, in any order, on build, craft, develop, trade, deploy, defend or dispatch. Passing is allowed. Cards may supply a narrowly documented free subaction but never create a third unrestricted Action Point. One on-turn Strategy Card play maximum.
4. **End:** discard to nine total held goods (keep any mix), settle expired temporary effects, check win after reactions, pass the device to next seat.

Every **three completed rounds**, advance season cyclically: Thaw → Bloom → Harvest → Frost. Seasonal boost applies after the die roll, once per matching producer: Thaw +1 wood at one woodland you occupy; Bloom +1 wool at one meadow; Harvest +1 wheat at one field; Frost +1 ore at one ridge. Only the current player chooses which one of their producing tiles receives the seasonal bonus; if none produced, no bonus. No bonus on 7. Public district demand rotates one market clockwise on every 7 and each season change. A district demand is one featured crafted good selected in cycle paper → cloth → coin; a matching Contract delivered there yields one bonus basic good in addition to its VP.

At each full-round boundary, Reaver Pressure increases by one and each player's Reaction Token resets to one. At pressure 4, pause before the next round's production and resolve an **Invasion** (then reset pressure to 0). This order is fixed for replay.

## Buildings, paths, craft and trade costs

All builds require connectivity through your roads to one of your Villages/Towns/Capitals; new Village needs an empty vertex at least one edge away from any holding. One paid build consumes one action:

| Action | Cost | Effect |
| --- | --- | --- |
| Road | 1 wood + 1 brick | Occupy a legal adjacent empty edge |
| Village | 1 wood + 1 brick + 1 wheat + 1 wool | 1 VP on a connected eligible vertex |
| Town | Upgrade own Village: 2 wheat + 2 ore | Replace Village's 1 VP with 2 VP; yields two basic goods |
| Capital | Upgrade own Town: 3 paper + 3 cloth + 3 coin; at least two development tracks level 4+ | Town's 2 VP becomes 4 VP (**+2 VP**) |
| Recruit knight | 1 wool + 1 ore | Place unready knight on a connected friendly vertex/edge |
| Ready knight | 1 wheat | Make one knight active until committed/exhausted |
| Repair road | 1 wood | Remove one toll/damage marker from your road |

Craft (one action) converts **1 wood + 1 wheat → 1 paper**, **1 wool + 1 wheat → 1 cloth**, or **1 ore + 1 brick → 1 coin**. Town required somewhere in network; one craft per action. Owning a Town Development level 1+ in the matching path permits drawing **one** Strategy Card from that deck immediately after a successful matching craft, maximum one drawn on your turn. Three-card hand maximum; if full, choose a card to discard before drawing.

Town Developments are per-player tracks, levels 0–5; each upgrade is one action, sequential, and pays the matching commodity (**paper Innovation**, **cloth Commerce**, **coin Governance**) plus a common good:

| Level reached | Matching crafted good | Extra good |
| --- | ---: | --- |
| 1 | 1 | wheat |
| 2 | 2 | wood |
| 3 | 2 | brick |
| 4 | 3 | ore |
| 5 | 4 | wheat |

Level 1 unlocks relevant card draws and basic path action. Level 2 Innovation allows one production result to be banked as a future season reserve (max 1); Commerce permits own **3:1** bank exchanges permanently; Governance makes one knight ready for free after each successful Invasion. Level 3 Innovation allows peeking the next forecast; Commerce carries two Contract goods per Caravan; Governance grants +1 to first committed knight per Invasion. Level 4 Innovation can substitute one basic good during a craft once per turn; Commerce earns one additional basic good from a completed Contract; Governance may shield one exposed Town from a failed Invasion by exhausting a knight. Level 5 Innovation gains one additional basic output of the chosen season, Commerce may complete two Contracts in one dispatch (still maximum two Charter VP), Governance adds +2 to total defence once per Invasion. All level 3–5 effects are non-stackable, no automatic VP. The engine must check prerequisites and resource conservation.

Trade with bank (one action): **4 identical goods → 1 basic good** of choice, except a connected generic port grants 3:1, a connected specialised port grants 2:1 for its listed good, or Commerce level 2 grants 3:1. Rates never stack below 2:1. Players may agree directly to arbitrary resource exchanges using an Offer reaction, with both sides explicitly accepting and both actually owning the goods. Trade with the bank cannot obtain crafted goods; these must be crafted or earned through effects that explicitly say so.

**Freight Relief:** a player at least three VP behind the current leader may once per round use **3 identical goods → 1 basic good** on their own turn, paying an action. It does not stack with ports or Commerce's 3:1, expires at round boundary, and provides zero free goods or Victory Points.

## Caravans, markets, contracts, Bandit

A Caravan is dispatched from an owned Town along a connected road path to any of three market vertices (one action, cost one wheat for travel). Max one active Caravan per player. Before arrival, open a **Caravan reaction window**. Any intervening Bandit road toll costs one coin to cross, unless an Escort prevents it; Blockade can impose an additional single-link toll. The owner may reroute along a longer eligible path (no added Action Point) or cancel and retrieve cargo, losing only travel wheat. Roads can be guarded by active knights.

At a market, deliver a public Contract (three shown and refreshed in fixed seeded order), typically **2 matching crafted goods + 1 named basic good**. Delivering consumes cargo and gains **1 Charter VP**, at most two over the whole match; the current demanded district also gives one chosen basic good from the bank. One Caravan can deliver one Contract unless Commerce level 5 applies. Caravan returns to its source after resolution. Completed contracts are public.

Bandit is a single road-edge toll marker, never an income-suppressing hex token. It relocates on a Market Shift, an explicit Strategy Card, or a Governance effect. It cannot occupy a market vertex or a road that has no eligible owner. Its toll is 1 coin paid to the bank, not a stolen random card.

## Reaver Fleet, Invasions, Guardian's Honour

At pressure 4 open an Invasion reaction window. Threat = **2 + current round / 3** (integer division), capped at 8; every active knight committed to defence contributes 1, plus Governance bonuses. All players may commit any number of their own ready knights for free when the invasion starts; an eligible Escort reaction adds +1 from one more newly readied/committed knight at cost 1 coin. Committed knights exhaust.

If total committed defence ≥ threat, invasion succeeds. The sole player who contributed the most knight strength (minimum 2, ties give no distinction) earns **1 Guardian's Honour VP**, maximum two lifetime, while each contributor gains one Influence (cap 3). No free points for lagging. If defence fails, each player with an unguarded Town must choose one and downgrade it to Village (**lose 1 VP**) or pay 2 coin to fortify it; each player can suffer at most one Town downgrade per Invasion. Capital never downgrades from a single failed Invasion. Reaver Fleet resets to 0 regardless. Declared defences and downgrades resolve in public seat order.

## Reaction windows and Strategy Cards

Each seat receives **one Reaction Token per full round**, usable only in another player's turn or during a shared Invasion. A reaction is an irrevocable revealed commitment; **Pass** spends nothing. Active player cannot react to their own window. Offered resource swaps need positive acceptance by the target. Windows are bounded and close once every eligible seat has committed/passed; Stage-7 asynchronous online play adds explicit deadlines and defaults to Pass (never silent cost). A player may play at most one Strategy Card as their reaction for the entire round, and that play uses their Reaction Token.

- **Offer**, Caravan window only: name exact goods offered and requested, escrow goods until the active player accepts; if declined, return goods.
- **Escort**, either window: commit a ready knight and pay one coin; prevent one Caravan toll or add +1 Invasion defence. Exhaust committed knight.
- **Blockade**, Caravan window only: commit a ready knight and pay one coin; toll one chosen traversed link until next round; can be countered by Escort, rerouting or paying one coin to the bank.

Resolve all commitments in clockwise seat order from the active player; for equal-time conflicts: Escorts apply before Blockades, then Offers, then route settlement. All costs and resource transfers are validated atomically; if cost fails, the commitment is rejected and its token is not spent. The stage-1 engine **only records reaction commitments and token use**; settlement arrives in Stage 4.

**Strategy Cards** are single-use, held in hands (max 3); deck identity green Innovation, yellow Commerce, blue Governance. All three decks contain twelve *unique* original effects with two copies each in the completed game, shuffled from saved seed. Players draw from a deck corresponding to a successful craft at level 1+ (max one draw/own turn) and can play one during their own turn and one as a reaction per full round. The six initial named effect families per deck and further twelve-card design task are in GLOSSARY. No card creates instant VP; VP remains attached to earned buildings, contracts and defence.

## Scoring, ties, information and disconnection

Score at all times is: **1 per Village + 2 per Town + 4 per Capital + Guardian's Honour (max 2) + Charter VP (max 2)**. Upgrading **replaces** old holding points (never adds both). The leader is current highest scored player; ties count as leaders for the gap calculation. Win check occurs after the current action and its reaction resolutions. Seed, turns, dice, deck shuffles, decision timestamps and responses belong to the saved replay event log. For offline pass-and-play, all players share one device with private hand handoff. Future online games must be server-authoritative and deterministic, not drive the engine from Compose side effects.
