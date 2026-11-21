# Stone & Banner completion 7/8 — AI fairness and balance (5 Nov 2026 NZDT)

## Decision

**Keep all production balance parameters unchanged.** Commerce-focused bots beat Innovation-focused bots consistently under controlled seat rotation. However, the reported first-seat advantage changes sharply with the AI policy and is not established as an engine-rule effect. Neither result authorizes a speculative nerf ahead of human/physical-gameplay acceptance.

This is a pure-Dart reducer study. No UI/device test, Samsung interaction, app installation or public release is claimed.

## Controlled design

- Isolated Glass worktree: feature/ai-fairness-20261105, based on origin/main f36c843. The main checkout and active mobile/LAN/Android/reconciliation worktrees were left untouched.
- Discovery seeds **12000–12119** and independent confirmation seeds **14000–14119**. Each seed was run at both 3 and 4 seats, rotating the exact AI lineup through every opening seat: **1,680 games**. Each seed block retains the same board seed (7*seed+11), rules, track focuses and trade/defence temperaments.
- Four-player teams duplicate one track, but cyclic rotation distributes every instance across every seat; total starts per track balance exactly.
- A separate identical-policy study used the existing legal-action HeuristicAi corpus on **9000–9239**, **12000–12119** and **14000–14119**: **1,920 additional games**, half all-AI and half weak legal-random simulated input. The latter is not a human.
- All runs used the unchanged MatchBalance.baseline and a 90-round cap. Censored games receive no winner. First-seat win share is conditioned on finished games; track wins per start retain censored games in the denominator.
- **95% intervals:** 5,000 fixed-seed bootstrap resamples of complete seed blocks for rotated games (preserving within-seed dependence); Wilson intervals for the independent identical-policy game counts. Exact computations are in the tracked analysis JSON and reproducible Python script.

## Track-focused, seat-rotated results

| Seats | Finished/games | First-seat wins / finished | 95% seed-block CI | Neutral |
| --- | ---: | ---: | ---: | ---: |
| 3 | 599/720 | 197/599 = **32.9%** | 29.4–36.5% | 33.3% |
| 4 | 866/960 | 199/866 = **23.0%** | 20.2–25.7% | 25.0% |

| Seats | Innovation wins/start | Commerce wins/start | Governance wins/start | Commerce − Innovation, 95% seed-block CI |
| --- | ---: | ---: | ---: | ---: |
| 3 | 102/720 = **14.2%** | 309/720 = **42.9%** | 188/720 = **26.1%** | **+28.8 pp** (+23.5 to +33.9 pp) |
| 4 | 113/1280 = **8.8%** | 495/1280 = **38.7%** | 258/1280 = **20.2%** | **+29.8 pp** (+26.3 to +33.4 pp) |

The discovery and independent confirmation cohorts each support the Commerce gap. This is robust within **this policy family**, not proof of equal or unequal human strategy strength.

## Opening seat across AI policies

| Policy and seeds | 3-player seat-0 share (95% CI) | 4-player seat-0 share (95% CI) |
| --- | ---: | ---: |
| Rotated track-focused, 240 seed blocks | **32.9%** (29.4–36.5%) | **23.0%** (20.2–25.7%) |
| Identical HeuristicAi, all 480 seeds | **200/448 = 44.6%** (40.1–49.3%) | **157/480 = 32.7%** (28.7–37.0%) |
| Identical HeuristicAi, same 240 seeds as rotated | **102/222 = 45.9%** (39.5–52.5%) | **73/240 = 30.4%** (24.9–36.5%) |
| Identical HeuristicAi, independent 240 seeds | **98/226 = 43.4%** (37.1–49.9%) | **84/240 = 35.0%** (29.2–41.2%) |

The earlier 4-seat result was **88 wins/280 scheduled games = 31.4%** (docs/E2E-AUDIT.md, Slice 08). The new all-AI study replicates the rough signal, but the track-focused lineup rotations do not. In particular, the 3-seat signal disappears with the other policy on the **same seed ranges**.

HeuristicAi greedily values opening production, breaks ties by lowest board index and defaults to Commerce development; the track-focused BalanceSimulation uses a different evaluator plus varied strategies. Those are plausible **policy mechanisms**, not proven single causes. Gameplay choices alter later seeded histories, and the snake draft may still have a genuine human advantage. A robust engine-rule effect is **not established**.

The historical Market Hall 4:1 nerf likewise failed independent confirmation (docs/BALANCE.md). No Commerce, catch-up, setup or rule parameter has been changed.

## Integrity and testing

- **1,680/1,680** rotated games completed or censored without a fatal error. Final replay export/import snapshots matched; finite resources including standing-offer escrow, physical Strategy Card stock and 15-VP victory checks passed in every run.
- **1,920/1,920** stability games finished or censored with **zero** legality, supply, replay, victory or timeout failures. Two-player games remain unsupported; no human test is implied.
- buildq **#5079** rotated discovery, **#5080** rotated confirmation, **#5081** independent stability, **#5088/#5089** same-seed stability: all passed.
- buildq **#5075** focused tests passed (before the final added regression assertion); **#5077** targeted analyzer passed; **#5078** corrected pilot passed. Earlier **#5074/#5076** failed on a missing import in the new harness, then were fixed.
- Final buildq **#5093**: **140 Flutter tests passed**; **#5094**: full lib/test/tool analyzer clean. The tests cover explicit policy rotation, bad lineup rejection and a **byte-identical event replay** between default simulation and the matching explicit lineup.
- buildq **#5092**: Android release APK built only, **54,890,298 bytes**, SHA-256 **98566657addb5d503418f032678d91d3132aeee35411513ac2b4831283d13ac9**. No installation or screenshot.
- Only research simulation input and study/test/report files changed. Production rules, deterministic replay format, Flutter UI, network code and runtime AI policy are untouched.

## Exact evidence and reproduction

Glass worktree: /home/brandon/worktrees/stone-ai-fairness-20261105

Tracked under docs/evidence/completion7_ai_fairness_20261105/:

- rotated-discovery.jsonl and rotated-confirmation.jsonl: all 1,680 seeded game outcomes, winning seats, track assignments, final scores, censored games and rotations.
- Two rotated summaries, three independently generated stability summaries, and analysis-all.json with the full-precision confidence intervals.
- Full stability per-game records and empty failure files also remain on Glass under build/ai-fairness-stability, build/ai-fairness-heuristic-a and build/ai-fairness-heuristic-b.

Commands from the worktree (using the compatible Flutter 3.47.6 / Dart 3.13.5 SDK):

    buildq --wait -- /home/brandon/.local/share/flutter-stone-and-banner-3.47.6/bin/dart run tool/ai_fairness_study.dart 12000 120 90 build/ai-fairness-discovery
    buildq --wait -- /home/brandon/.local/share/flutter-stone-and-banner-3.47.6/bin/dart run tool/ai_fairness_study.dart 14000 120 90 build/ai-fairness-confirm
    buildq --wait -- /home/brandon/.local/share/flutter-stone-and-banner-3.47.6/bin/dart run tool/ai_stability_corpus.dart 9000 240 90 build/ai-fairness-stability

Recompute intervals directly from tracked evidence:

    python tool/analyze_ai_fairness.py --rotated docs/evidence/completion7_ai_fairness_20261105/rotated-discovery.jsonl docs/evidence/completion7_ai_fairness_20261105/rotated-confirmation.jsonl --stability docs/evidence/completion7_ai_fairness_20261105/heuristic-independent-summary.json docs/evidence/completion7_ai_fairness_20261105/heuristic-matched-a-summary.json docs/evidence/completion7_ai_fairness_20261105/heuristic-matched-b-summary.json --output build/ai-fairness-recomputed.json

**Handoff:** Commit this isolated study and push its own feature branch. The primary checkout is dirty and other Stone & Banner completion slices own overlapping UI/gameplay work; do not merge or reset their main checkout. Stage 8 physical/human gameplay acceptance remains the decision gate for actual balance changes.
