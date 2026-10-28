# Stage 4 Strategy Card balance ledger — 28 October 2026

This is a **measured event/deck baseline**, not proof of equal match win rates. Stage 7 must run full-game strategy equity simulations, including target selection and opponent counterplay.

## Acquisition and supply

- Three decks, each **18 physical copies**. Innovation: 10 distinct names (eight pairs and two singles). Commerce: 9 pairs. Governance: 9 pairs.
- Every numbered roll also produces a deterministic event die (1–6) and tier die (1–5), derived from the saved seed and roll index. Faces 1/2/3 offer Innovation/Commerce/Governance; faces 4–6 are calm.
- Each seat whose matching development level is at least the tier die earns one card, if below the four-card hand limit. Draw order rotates from the roller, then clockwise. All players share each deck. Empty piles reshuffle spent copies deterministically, but never cards still in hands.
- Draws and plays enter the event-derived state; play and discard are explicit replay events. Invalid targets cannot consume cards. Unplayable cards can always be kept or discarded during the action phase. Card identities are not published in the public event report.

## Quantitative targets and observed deviations

30,000 seeded event/tier checks: seeds 1–300, roll indices 1–100 per seed, with the engine's unsigned 32-bit xorshift. The same sampling is enforced by `strategy_cards_test.dart`.

| Metric | Target | Observed | Deviation |
| --- | ---: | ---: | ---: |
| Innovation event face | 16.67% ±2 percentage points | 17.08% | +0.41 pp |
| Commerce event face | 16.67% ±2 pp | 16.51% | −0.16 pp |
| Governance event face | 16.67% ±2 pp | 16.37% | −0.30 pp |
| Innovation qualifying draw at level III | 10.00% ±2 pp/roll | 10.06% | +0.06 pp |
| Commerce qualifying draw at level III | 10.00% ±2 pp/roll | 9.89% | −0.11 pp |
| Governance qualifying draw at level III | 10.00% ±2 pp/roll | 9.71% | −0.29 pp |

Theoretical per-seat chance on **each table roll**, with an available deck slot and hand space: level I 3.33%, level III 10.00%, level V 16.67%. This is not a promise of cards-per-round, because hands can fill and finite physical copies can be held by other players.

## Functional guardrails and open deviations

- Resource-gain cards move **one or two goods from the finite bank**; no direct victory points or invented goods. Trade cards pay a bank cost before receiving a bank-stock-limited benefit.
- A Commerce exchange changes one or two goods and cannot bypass conserved stock. Blue seizure transfers **one** owned good; green builds at most one road or one fortification; blue Knight powers change one Knight state. Every effect has reducer-level validation.
- Green leans infrastructure (five build/fortify copies); yellow has six swap copies and twelve stock-claim copies; blue has eight Knight/Bandit-control copies, four single-good seizure copies and six bank-supply copies. The 18-copy counts are equal; economic value and tactical impact are not assumed equivalent.
- **Open balance deviations:** a free fortification saves a three-good normal cost, and a free Warden-to-Champion promotion saves three goods; those exceed the two-good direct-supply ceiling but are situational and target-dependent. A Knight stand-down can suppress up to three collective defence. A seized good creates a two-seat swing. These need Stage 7 empirical payoff/seat-equity checks; no win-rate claim has been made.
- Stage 7 targets to measure: max **±5 pp** first-seat win-rate deviation from even-seat baseline across randomized seeds; max **±5 pp** between tracks at matched development levels/hand opportunities; no permanent action-phase stalls across 10,000 random legal turns. These are proposed acceptance thresholds, **not yet measured**.

Replay, per-resource conservation and physical-copy accounting are regression tested for representative card effects, invalid targets, discard, overflow, exhaustion and natural acquisition. Android UI/card targeting tests are in `strategy_cards_widget_test.dart`.
