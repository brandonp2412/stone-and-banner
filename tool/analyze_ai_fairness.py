#!/usr/bin/env python3
"""Recompute Stone & Banner AI fairness intervals from recorded seeded matches.

Use independent seed blocks as resampling units for cyclically rotated games;
do not treat rotations of one seed/board as independent observations.
"""

import argparse
from collections import defaultdict
import json
from math import sqrt
from pathlib import Path
from random import Random


TRACKS = ("innovation", "commerce", "governance")


def load_records(paths):
    records = []
    for path in paths:
        records.extend(
            json.loads(line)
            for line in Path(path).read_text().splitlines()
            if line.strip()
        )
    return records


def counts(records):
    starts = {track: 0 for track in TRACKS}
    wins = {track: 0 for track in TRACKS}
    finished = 0
    first_wins = 0
    for game in records:
        for track in game["seatTracks"]:
            starts[track] += 1
        if not game["finished"]:
            continue
        finished += 1
        if game["winnerSeat"] == 0:
            first_wins += 1
        wins[game["winnerTrack"]] += 1
    return {
        "games": len(records),
        "finished": finished,
        "first_wins": first_wins,
        "starts": starts,
        "wins": wins,
    }


def total(blocks):
    result = {
        "games": 0,
        "finished": 0,
        "first_wins": 0,
        "starts": {track: 0 for track in TRACKS},
        "wins": {track: 0 for track in TRACKS},
    }
    for block in blocks:
        for field in ("games", "finished", "first_wins"):
            result[field] += block[field]
        for track in TRACKS:
            result["starts"][track] += block["starts"][track]
            result["wins"][track] += block["wins"][track]
    return result


def measures(c):
    first_share = c["first_wins"] / c["finished"] if c["finished"] else 0
    rates = {
        track: c["wins"][track] / c["starts"][track]
        if c["starts"][track]
        else 0
        for track in TRACKS
    }
    return first_share, rates, rates["commerce"] - rates["innovation"]


def interval(values):
    values.sort()
    return [values[int(len(values) * 0.025)],
            values[int(len(values) * 0.975) - 1]]


def rotated_stats(records, seats, bootstrap_samples=5000):
    matches = [r for r in records if r["seats"] == seats]
    seeds = defaultdict(list)
    for match in matches:
        seeds[match["seed"]].append(match)
    for seed, group in seeds.items():
        if len(group) != seats or {x["rotation"] for x in group} != set(range(seats)):
            raise ValueError(f"Incomplete seat rotation for seed={seed}, seats={seats}")
    blocks = [counts(seeds[seed]) for seed in sorted(seeds)]
    c = total(blocks)
    share, rates, diff = measures(c)
    rng = Random(20261105 + seats + len(blocks))
    seat_draws, diff_draws = [], []
    for _ in range(bootstrap_samples):
        sample = total([blocks[rng.randrange(len(blocks))]
                        for _ in range(len(blocks))])
        s, _, d = measures(sample)
        seat_draws.append(s)
        diff_draws.append(d)
    return {
        "seats": seats,
        "seed_blocks": len(blocks),
        "games": c["games"],
        "finished": c["finished"],
        "capped": c["games"] - c["finished"],
        "first_seat_wins": c["first_wins"],
        "first_seat_share": share,
        "first_seat_ci95_block_bootstrap": interval(seat_draws),
        "neutral_first_seat_share": 1 / seats,
        "track_starts": c["starts"],
        "track_wins": c["wins"],
        "track_win_per_start": rates,
        "commerce_minus_innovation": diff,
        "commerce_minus_innovation_ci95_block_bootstrap": interval(diff_draws),
    }


def wilson(wins, total_games, z=1.959963984540054):
    if not total_games:
        return [None, None]
    p = wins / total_games
    z2 = z * z
    center = (p + z2 / (2 * total_games)) / (1 + z2 / total_games)
    half = z * sqrt(
        p * (1 - p) / total_games + z2 / (4 * total_games**2)
    ) / (1 + z2 / total_games)
    return [center - half, center + half]


def stability_stats(paths):
    cohorts = defaultdict(lambda: {"games": 0, "finished": 0, "wins": []})
    for path in paths:
        report = json.loads(Path(path).read_text())
        if report["failures"]:
            raise ValueError(f"Stability corpus reported failures: {path}")
        for cohort in report["cohorts"]:
            key = (cohort["seats"], cohort["mode"])
            row = cohorts[key]
            row["games"] += cohort["games"]
            row["finished"] += cohort["finished"]
            if not row["wins"]:
                row["wins"] = [0] * cohort["seats"]
            row["wins"] = [
                a + b for a, b in zip(row["wins"],
                                      cohort["winsByOpeningSeat"])
            ]
    return [
        {
            "seats": seats,
            "mode": mode,
            "games": c["games"],
            "finished": c["finished"],
            "capped": c["games"] - c["finished"],
            "first_seat_wins": c["wins"][0],
            "first_seat_share_finished": c["wins"][0] / c["finished"],
            "first_seat_ci95_wilson": wilson(c["wins"][0], c["finished"]),
            "neutral_first_seat_share": 1 / seats,
            "wins_by_seat": c["wins"],
        }
        for (seats, mode), c in sorted(cohorts.items())
    ]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--rotated", nargs="+", required=True)
    parser.add_argument("--stability", nargs="+", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    matches = load_records(args.rotated)
    report = {
        "methods": {
            "rotated": "5000 seeded bootstrap resamples of complete seed blocks",
            "stability": "Wilson binomial intervals on finished games",
            "censoring": "capped games excluded from first-seat winner denominator; "
                         "retained in per-track start denominators",
        },
        "rotated": [rotated_stats(matches, seats) for seats in (3, 4)],
        "stability": stability_stats(args.stability),
    }
    output = json.dumps(report, indent=2) + "\n"
    Path(args.output).write_text(output)
    print(output)


if __name__ == "__main__":
    main()
