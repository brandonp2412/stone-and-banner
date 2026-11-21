# Slice 08 — 90-round censored matches

51 of 1120 main-corpus matches did not reach 15 VP by the specified 90-round horizon. These are **not** reducer exceptions or event-cap timeouts. Re-run with the same seed, seats, policy mode and a higher round cap to investigate late outcomes.

| Seed | Seats | Policy | Simulated-human seat | Final VP by seat | Events | Range |
| ---: | ---: | --- | ---: | --- | ---: | --- |
| 7223 | 3 | allAi | — | 8, 6, 8 | 1362 | corpus |
| 7278 | 3 | allAi | — | 4, 4, 3 | 1343 | corpus |
| 7202 | 3 | simulatedHuman | 2 | 9, 8, 4 | 1383 | corpus |
| 7223 | 3 | simulatedHuman | 2 | 5, 10, 3 | 1330 | corpus |
| 7225 | 3 | simulatedHuman | 1 | 8, 2, 9 | 1384 | corpus |
| 7235 | 3 | simulatedHuman | 2 | 10, 11, 2 | 1392 | corpus |
| 7239 | 3 | simulatedHuman | 0 | 2, 10, 9 | 1418 | corpus |
| 7266 | 3 | simulatedHuman | 0 | 2, 2, 2 | 1353 | corpus |
| 7275 | 3 | simulatedHuman | 0 | 3, 13, 12 | 1418 | corpus |
| 7278 | 3 | simulatedHuman | 0 | 2, 3, 4 | 1328 | corpus |
| 7603 | 3 | allAi | — | 12, 12, 14 | 1449 | confirmation |
| 7605 | 3 | allAi | — | 13, 13, 13 | 1381 | confirmation |
| 7610 | 3 | allAi | — | 8, 8, 9 | 1400 | confirmation |
| 7633 | 3 | allAi | — | 12, 9, 11 | 1415 | confirmation |
| 7636 | 3 | allAi | — | 3, 4, 4 | 1355 | confirmation |
| 7637 | 3 | allAi | — | 9, 12, 12 | 1435 | confirmation |
| 7643 | 3 | allAi | — | 6, 4, 7 | 1379 | confirmation |
| 7711 | 3 | allAi | — | 13, 11, 11 | 1416 | confirmation |
| 7745 | 3 | allAi | — | 10, 9, 6 | 1408 | confirmation |
| 7755 | 3 | allAi | — | 9, 9, 9 | 1396 | confirmation |
| 7773 | 3 | allAi | — | 8, 12, 11 | 1410 | confirmation |
| 7776 | 3 | allAi | — | 12, 13, 10 | 1402 | confirmation |
| 7600 | 3 | simulatedHuman | 1 | 12, 2, 9 | 1395 | confirmation |
| 7605 | 3 | simulatedHuman | 0 | 2, 7, 12 | 1407 | confirmation |
| 7607 | 3 | simulatedHuman | 2 | 8, 5, 4 | 1356 | confirmation |
| 7608 | 3 | simulatedHuman | 0 | 2, 10, 9 | 1364 | confirmation |
| 7610 | 3 | simulatedHuman | 2 | 11, 14, 4 | 1450 | confirmation |
| 7621 | 3 | simulatedHuman | 1 | 6, 2, 4 | 1337 | confirmation |
| 7624 | 3 | simulatedHuman | 1 | 4, 4, 6 | 1342 | confirmation |
| 7629 | 3 | simulatedHuman | 0 | 2, 9, 13 | 1388 | confirmation |
| 7635 | 3 | simulatedHuman | 0 | 2, 4, 3 | 1372 | confirmation |
| 7636 | 3 | simulatedHuman | 1 | 2, 4, 4 | 1360 | confirmation |
| 7654 | 3 | simulatedHuman | 1 | 7, 4, 8 | 1366 | confirmation |
| 7672 | 3 | simulatedHuman | 1 | 3, 2, 7 | 1353 | confirmation |
| 7691 | 3 | simulatedHuman | 2 | 11, 8, 4 | 1334 | confirmation |
| 7695 | 3 | simulatedHuman | 0 | 2, 6, 8 | 1357 | confirmation |
| 7699 | 3 | simulatedHuman | 1 | 12, 6, 9 | 1358 | confirmation |
| 7713 | 3 | simulatedHuman | 0 | 2, 9, 10 | 1420 | confirmation |
| 7729 | 3 | simulatedHuman | 1 | 7, 2, 9 | 1406 | confirmation |
| 7734 | 3 | simulatedHuman | 0 | 2, 12, 10 | 1359 | confirmation |
| 7736 | 3 | simulatedHuman | 2 | 11, 12, 2 | 1397 | confirmation |
| 7744 | 3 | simulatedHuman | 1 | 2, 2, 5 | 1318 | confirmation |
| 7750 | 3 | simulatedHuman | 1 | 9, 4, 8 | 1373 | confirmation |
| 7755 | 3 | simulatedHuman | 0 | 2, 6, 3 | 1323 | confirmation |
| 7773 | 3 | simulatedHuman | 0 | 2, 4, 5 | 1309 | confirmation |
| 7774 | 3 | simulatedHuman | 1 | 11, 2, 11 | 1400 | confirmation |
| 7782 | 3 | simulatedHuman | 0 | 2, 4, 6 | 1355 | confirmation |
| 7783 | 3 | simulatedHuman | 1 | 7, 2, 9 | 1360 | confirmation |
| 7785 | 3 | simulatedHuman | 0 | 4, 9, 10 | 1416 | confirmation |
| 7790 | 3 | simulatedHuman | 2 | 7, 5, 2 | 1310 | confirmation |
| 7736 | 4 | simulatedHuman | 0 | 2, 13, 12, 14 | 1945 | confirmation |

The complete event-type counts and action timings for every game are in `corpus/records.jsonl` and `confirmation/records.jsonl`. No upper-round continuation beyond 90 was run in this slice.
