import 'dart:convert';
import 'dart:io';

import 'package:stone_and_banner/engine/balance.dart';
import 'package:stone_and_banner/engine/game.dart';
import 'package:stone_and_banner/engine/simulation.dart';

void main(List<String> args) {
  final samples = args.isEmpty ? 12 : int.parse(args[0]);
  final maxRounds = args.length < 2 ? 65 : int.parse(args[1]);
  final selected = args.length > 3 ? args[3].split(',') : <String>[];
  final firstSeed = args.length > 4 ? int.parse(args[4]) : 1000;
  final variants = {
    'original': MatchBalance.baseline,
    'trailing_2_to_1': MatchBalance.enhancedTrade,
    'relief_after_2_dry': MatchBalance.earlierRelief,
    'stoneworks_at_III': MatchBalance.slowerStoneworks,
    'stoneworks_cheaper_paper': MatchBalance.cheaperStoneworks,
    'guild_3_to_1': MatchBalance.slowerGuild,
    'bazaar_single_good': MatchBalance.weakerBazaar,
    'market_4_to_1': MatchBalance.slowerMarket,
  };
  final report = <String, Object>{};
  for (final variant in variants.entries.where(
    (e) => selected.isEmpty || selected.contains(e.key),
  )) {
    var completed = 0,
        firstWins = 0,
        deficitGames = 0,
        deficitSeats = 0,
        comebackWins = 0,
        rounds = 0,
        turns = 0,
        dead = 0,
        reactions = 0,
        reacted = 0;
    final win = {for (final t in StrategyDeck.values) t.name: 0};
    final present = {for (final t in StrategyDeck.values) t.name: 0};
    final cardPlays = {for (final t in StrategyDeck.values) t.name: 0};
    final cardValue = {for (final t in StrategyDeck.values) t.name: 0.0};
    for (var i = 0; i < samples; i++) {
      final result = BalanceSimulation.run(
        seed: firstSeed + i,
        seats: i % 4 == 0 ? 4 : 3,
        balance: variant.value,
        maxRounds: maxRounds,
      );
      for (final bot in result.bots) {
        present[bot.track.name] = present[bot.track.name]! + 1;
      }
      for (final track in StrategyDeck.values) {
        cardPlays[track.name] =
            cardPlays[track.name]! + result.cardPlays[track]!;
        cardValue[track.name] =
            cardValue[track.name]! + result.cardValue[track]!;
      }
      if (result.finished) {
        completed++;
        final w = result.winner!;
        if (w == 0) firstWins++;
        win[result.bots[w].track.name] = win[result.bots[w].track.name]! + 1;
        if (result.deficitSeats.contains(w)) comebackWins++;
      }
      if (result.deficitSeats.isNotEmpty) deficitGames++;
      deficitSeats += result.deficitSeats.length;
      rounds += result.completedRounds;
      turns += result.turns;
      dead += result.unproductiveRounds;
      reactions += result.reactionOpportunities;
      reacted += result.reactionUses;
    }
    double fraction(int n, int d) => d == 0 ? 0 : n / d;
    report[variant.key] = {
      'games': samples,
      'completed': completed,
      'capped': samples - completed,
      'firstSeatWinShareCompleted': fraction(firstWins, completed),
      'trackWins': win,
      'trackWinRateStarts': {
        for (final t in StrategyDeck.values)
          t.name: fraction(win[t.name]!, present[t.name]!),
      },
      'comebackAfter3VpDeficitAt8PlusLeaderVp': {
        'wins': comebackWins,
        'gamesWithTrailingSeat': deficitGames,
        'eligibleTrailingSeats': deficitSeats,
        'probabilityPerEligibleSeat': fraction(comebackWins, deficitSeats),
        'probabilityPerEligibleGame': fraction(comebackWins, deficitGames),
      },
      'meanTurns': fraction(turns, samples),
      'meanFullRounds': fraction(rounds, samples),
      'unproductiveRounds': dead,
      'unproductiveRoundShare': fraction(dead, rounds),
      'reactionOpportunities': reactions,
      'reactionUses': reacted,
      'reactionUseShare': fraction(reacted, reactions),
      'cardPlays': cardPlays,
      'cardEffectValuePerUse': {
        for (final t in StrategyDeck.values)
          t.name: double.parse(
            fraction(
              (cardValue[t.name]! * 100).round(),
              cardPlays[t.name]! * 100,
            ).toStringAsFixed(2),
          ),
      },
    };
  }
  final output = const JsonEncoder.withIndent('  ').convert(report);
  if (args.length > 2) {
    File(args[2]).writeAsStringSync('$output\n');
    stdout.writeln('Saved metrics to ${args[2]}');
  } else {
    stdout.writeln(output);
  }
}
