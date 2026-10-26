# Economy and reaction balance hypotheses

These are testable **hypotheses**, not claims that balance has been achieved. Implement telemetry-free local seeded simulations (no personal data) in Stage 5.

## Trailing-player relief

- A player at least **3 Victory Points** behind the current leader may make **one** bank exchange at **3 same goods : 1 chosen good** on their own turn per round; ordinary bank rate **4:1**. Ports retain their independently available rates; never stack reductions.
- Consumes actual goods and an action. No cards, Victory Points or buildings are gifted. Current score, not historical ranking, determines eligibility.
- Target: trailing player within 10 percentage points of comeback probability versus control when behind 3 VP at midpoint, but leader retains meaningful advantage. Target total match duration within ±10% of control.
- Guardrails: no eligibility at tie/2-point gap, no turn carryover, cap one relief exchange per completed round, cannot create a free good.

## Three equally attractive strategies

| Track | Principal benefit | Tradeoff | Balance metric |
| --- | --- | --- | --- |
| Innovation/green | Production certainty, recipe efficiency, logistics | Requires early paper/Wood-Wheat investment | Adjusted expected goods saved per 3 rounds |
| Commerce/yellow | Contract delivery, ports, barter | Relies on road network and trading partners | Net goods-equivalent per action |
| Governance/blue | Reaver defence, knights, reaction leverage | Requires maintaining knight readiness | Prevented loss + Influence utility |

- Draw opportunity: craft path-matched commodity with that track at level 1+; at most **one** Strategy Card drawn per own turn, hand limit 3. Draws are from seeded/shuffled balanced pools, not tied to lucky die faces. One on-turn card play maximum; one reaction play per round if reaction token available.
- Each deck eventually has **12 unique cards × 2 copies**. Target first-player win rate 25% ± 5 points in 4-player symmetric policy simulations; each primary path selected by ≥25% of competent-policy winners. Stress-test pure and hybrid tracks, with pairwise head-to-head matrices.
- No permanent stacking discounts under bank rate 2:1; no instant Strategy Card VP; every effect has a readable opponent response or bounded cost.

## Out-of-turn participation

- One Reaction Token per player per full round, refresh on round start. A valid commitment consumes it; Pass does not.
- **Offer** during Caravan dispatch: propose exact resource swap; active player may accept, never forced.
- **Escort** during Caravan or Invasion: commit an active knight/one coin to protect cargo or add +1 defence; actual resource exhaustion resolves atomically.
- **Blockade** during Caravan: pay one coin and commit knight to place a one-link toll until next round; opponent may reroute or pay.
- Window resolves seat order, with consent requests before swaps; cannot act twice or react to one's own action. No automatic stalling after all have passed/responded; asynchronous deadlines in Stage 7 only.
- Target: median 1+ non-active player decision per round, additional turn time under 15%, and no dominant blocking loop. Forced-loss scenarios must offer visible fallback.
