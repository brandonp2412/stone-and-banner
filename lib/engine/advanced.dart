import 'board.dart';
import 'game.dart';

enum GuardRank {
  sentinel(1),
  warden(2),
  champion(3);

  const GuardRank(this.strength);
  final int strength;
}

class GuardPiece {
  const GuardPiece(this.owner, this.rank, this.active, this.actedTurn);
  final int owner, actedTurn;
  final GuardRank rank;
  final bool active;

  GuardPiece copyWith({GuardRank? rank, bool? active, int? actedTurn}) =>
      GuardPiece(
        owner,
        rank ?? this.rank,
        active ?? this.active,
        actedTurn ?? this.actedTurn,
      );
}

extension TownDevelopments on StrategyDeck {
  Resource get commodity => switch (this) {
    StrategyDeck.innovation => Resource.paper,
    StrategyDeck.commerce => Resource.cloth,
    StrategyDeck.governance => Resource.coin,
  };

  Land get sourceLand => switch (this) {
    StrategyDeck.innovation => Land.woodland,
    StrategyDeck.commerce => Land.meadows,
    StrategyDeck.governance => Land.ridges,
  };

  List<String> get tiers => switch (this) {
    StrategyDeck.innovation => const [
      'Scriptorium',
      'Stoneworks',
      'Reservoir',
      'Supply Network',
      'Observatory',
    ],
    StrategyDeck.commerce => const [
      'Loomhouse',
      'Market Hall',
      'Trade Wharf',
      'Guild Exchange',
      'Grand Bazaar',
    ],
    StrategyDeck.governance => const [
      'Mint House',
      'Watchtower',
      'Fortifications',
      "Marshal's Hall",
      'High Council',
    ],
  };

  Map<Resource, int> costFor(int level) {
    if (level < 1 || level > 5) throw StateError('Invalid development level.');
    return {
      Resource.wheat: 1,
      Resource.ore: level == 1 ? 1 : 2,
      if (level > 1) commodity: level - 1,
    };
  }
}
