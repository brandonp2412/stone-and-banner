/// Immutable, replayed rule parameters for controlled balance experiments.
class MatchBalance {
  const MatchBalance({
    this.catchupRate = 3,
    this.reliefRolls = 3,
    this.stoneworksTier = 2,
    this.innovationTier2Paper = 1,
    this.marketRate = 3,
    this.guildRate = 2,
    this.bazaarGoods = 2,
    this.raidBonusAfterFirst = 1,
    this.guardianHonourCap = 2,
    this.raidAidCap = 2,
  }) : assert(catchupRate >= 2 && catchupRate <= 4),
       assert(reliefRolls >= 2 && reliefRolls <= 4),
       assert(stoneworksTier >= 2 && stoneworksTier <= 3),
       assert(innovationTier2Paper >= 0 && innovationTier2Paper <= 1),
       assert(marketRate >= 3 && marketRate <= 4),
       assert(guildRate >= 2 && guildRate <= 3),
       assert(bazaarGoods >= 1 && bazaarGoods <= 2),
       assert(raidBonusAfterFirst >= 0 && raidBonusAfterFirst <= 2),
       assert(guardianHonourCap >= 0 && guardianHonourCap <= 5),
       assert(raidAidCap >= 0 && raidAidCap <= 2);

  final int catchupRate;
  final int reliefRolls;
  final int stoneworksTier;
  final int innovationTier2Paper;
  final int marketRate, guildRate, bazaarGoods;

  /// Extra raid strength after the first invasion; zero means old rules.
  final int raidBonusAfterFirst;

  /// Max Honour points from defences; zero means old unlimited rules.
  final int guardianHonourCap;

  /// Shared emergency defence per raid. Zero preserves uncapped aid.
  final int raidAidCap;

  static const baseline = MatchBalance();
  static const legacy = MatchBalance(
    raidBonusAfterFirst: 0,
    guardianHonourCap: 0,
    raidAidCap: 0,
  );
  static const enhancedTrade = MatchBalance(catchupRate: 2);
  static const earlierRelief = MatchBalance(reliefRolls: 2);
  static const slowerStoneworks = MatchBalance(stoneworksTier: 3);
  static const cheaperStoneworks = MatchBalance(innovationTier2Paper: 0);
  static const slowerGuild = MatchBalance(guildRate: 3);
  static const weakerBazaar = MatchBalance(bazaarGoods: 1);
  static const slowerMarket = MatchBalance(marketRate: 4);

  Map<String, int> toJson() => {
    'catchupRate': catchupRate,
    'reliefRolls': reliefRolls,
    'stoneworksTier': stoneworksTier,
    'innovationTier2Paper': innovationTier2Paper,
    'marketRate': marketRate,
    'guildRate': guildRate,
    'bazaarGoods': bazaarGoods,
    'raidBonusAfterFirst': raidBonusAfterFirst,
    'guardianHonourCap': guardianHonourCap,
    if (raidAidCap > 0) 'raidAidCap': raidAidCap,
  };

  factory MatchBalance.fromJson(Map<String, dynamic>? json) {
    // Older saved games predate these rules; keep their replays deterministic.
    if (json == null) return legacy;
    int read(String key, int fallback, int minimum, int maximum) {
      final value = json[key] ?? fallback;
      if (value is! int || value < minimum || value > maximum) {
        throw FormatException('Invalid balance parameter: $key');
      }
      return value;
    }

    return MatchBalance(
      catchupRate: read('catchupRate', 3, 2, 4),
      reliefRolls: read('reliefRolls', 3, 2, 4),
      stoneworksTier: read('stoneworksTier', 2, 2, 3),
      innovationTier2Paper: read('innovationTier2Paper', 1, 0, 1),
      marketRate: read('marketRate', 3, 3, 4),
      guildRate: read('guildRate', 2, 2, 3),
      bazaarGoods: read('bazaarGoods', 2, 1, 2),
      raidBonusAfterFirst: read('raidBonusAfterFirst', 0, 0, 2),
      guardianHonourCap: read('guardianHonourCap', 0, 0, 5),
      raidAidCap: read('raidAidCap', 0, 0, 2),
    );
  }
}
