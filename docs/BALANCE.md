# Balance measurement and Stage 7 decisions

Stage 7 implements `lib/engine/simulation.dart` and `tool/balance.dart`.
The production rules remain `MatchBalance.baseline`; experimental immutable
parameters are serialized in replays, never silently selected in the UI.

## Reproduce on local test host

```sh
buildq --wait -- dart run tool/balance.dart 120 90 docs/STAGE7-METRICS.json
buildq --wait -- dart run tool/balance.dart 240 90 docs/STAGE7-CONFIRM.json original,market_4_to_1 2000
buildq --wait -- flutter test
```

Seeds 1000–1119 and independent confirmation seeds 2000–2239.
Board seeds are `7 * seed + 11`. Every fourth match has four seats; other
matches have three. Each track starts equally often. Trading and defence
temperaments rotate independently of track and opening seat. Bots place
legal settlements/roads, upgrade and develop, negotiate and bank-trade, play
Strategy Cards, defend and resolve seeded tactical windows via the **same
pure reducer** as hot-seat and LAN modes. No free goods or synthetic VP.

Results are bounded at 90 full rounds. Capped games are **not** credited to
any track. This is a deterministic sensitivity study, not proof of optimal
human play or statistical balance. The bots have one family of heuristics;
reaction, card valuation and long-horizon planning are approximate.

## Confirmed original-rules metrics: 360 games

- Finished: **304/360**; 56 capped.
- Wins by focused track: Innovation **44**, Commerce **162**, Governance **98**.
  Each track had **390 starts**; win rates per start **11.3%, 41.5%, 25.1%**
  respectively (capped games remain in denominators).
- First seat: **101/304 wins (33.2%)** versus a neutral 31.25% expected
  for the mixed three-/four-seat sample.
- Late comeback: **181/908 (19.9%)** of seats recorded at least 3 VP behind
  after a leader reached 8 VP later won.
- Mean turns entered: **220.5** per game (including censored matches).
  Unproductive full rounds: **1,101/24,517 (4.49%)**. A round counts
  unproductive if no build, development, recruitment, card play, bank
  exchange or accepted trade occurred.
- Tactical responses: **6,859/28,065 opportunities (24.4%)** used;
  opportunities count each eligible responder, including pass.
- Strategy Card immediate estimated value per play: Innovation **~2.05**,
  Commerce **~1.20**, Governance **~1.29** material-good equivalents.
  Valuation weights basic goods=1, commodities=1.5, road=2,
  fortification=2.5, active Knight rank=1–3, VP=5. These are immediate
  proxy changes, **not** long-term strategic value.

## Paired alternatives and decision

The 120-seed comparison tested once/round trailing bank trade 2:1,
earlier drought relief (after 2 dry rolls), later Stoneworks discount (III),
cheaper Stoneworks paper cost, Guild Exchange 3:1, Grand Bazaar single
good, and no Market Hall 3:1 discount. The complete compact summaries
are in `STAGE7-METRICS.json`.

Market Hall 4:1 looked promising on the first 120 seeds: Commerce wins
fell from **56 to 46**, while Innovation rose **15 to 21**, but completion
fell **104 to 102** and mean turns increased **217.5 to 226.0**.
On 240 independent confirmation seeds, Commerce wins instead rose
**106 to 111**, and both variants finished **200** games. Other alternatives
did not reliably improve completion, recovery and strategy equity together.
The Bazaar change produced identical outcomes in the initial sample,
suggesting that its tier-V benefit was rarely decisive for these bots.

**Decision:** retain every established default (Market Hall 3:1 at II,
Guild Exchange 2:1 at IV, Stoneworks discount at II, bounded 3:1
recovery and once-per-season dry relief). No direct VP bonuses, extra
green acceleration or unmeasured rubber-banding. Commerce's high bot
win share is an open balance risk to revisit with broader bot policies
and human sessions during Stage 8. The study explicitly does **not**
claim the tracks are equally balanced.
