import 'dart:convert';

import '../engine/advanced.dart';
import '../engine/board.dart';
import '../engine/cards.dart';
import '../engine/game.dart';
import '../engine/match.dart';

/// Wire format is a view, never a canonical reducer state or replay.
abstract final class RoomProtocol {
  static Map<String, dynamic> view(MatchState state, int seat) {
    final data =
        jsonDecode(MatchEngine.snapshot(state)) as Map<String, dynamic>;
    data['seed'] = 0; // The secret seed governs dice, theft and hidden decks.
    data['boardTiles'] = [
      for (final t in state.board.tiles)
        [t.position.q, t.position.r, t.land.name, t.productionNumber],
    ];
    data['events'] = <Object>[]; // Events can reveal private cards and goods.
    data['drawPiles'] = <String, Object>{};
    data['discardPiles'] = <String, Object>{};
    data['eventCount'] = state.events.length;
    data['handCounts'] = [for (final p in state.players) p.cards.length];
    final players = data['players'] as List;
    for (var i = 0; i < players.length; i++) {
      if (i == seat) continue;
      final other = players[i] as Map<String, dynamic>;
      other['resources'] = List.filled(Resource.values.length, 0);
      other['cards'] = <Object>[];
    }
    data['victims'] = <String, Object>{
      if (seat == state.active && state.phase == MatchPhase.bandit)
        for (var t = 0; t < state.board.tiles.length; t++)
          '$t': MatchEngine.banditVictims(state, t),
    };
    data['options'] = <String, Object>{
      if (seat == state.active &&
          state.phase == MatchPhase.actions &&
          state.tactical == null)
        for (var i = 0; i < state.current.cards.length; i++)
          '$i': [
            for (final event in MatchEngine.legalCardPlays(state, i))
              event.toJson(),
          ],
    };
    return data;
  }

  static MatchState readView(Map<String, dynamic> data) {
    List<dynamic> list(String key) => data[key] as List<dynamic>;
    int number(String key) => data[key] as int;
    final board = Board(0, [
      for (final item in list('boardTiles'))
        HexTile(
          HexCoord((item as List)[0] as int, item[1] as int),
          Land.values.byName(item[2] as String),
          item[3] as int?,
        ),
    ]);
    final initialPlayers = [
      for (final raw in list('players'))
        PlayerState(
          id: (raw as Map)['name'] as String,
          stores: {
            for (var i = 0; i < Resource.values.length; i++)
              Resource.values[i]: (raw['resources'] as List)[i] as int,
          },
          guardianHonour: raw['honour'] as int,
          charterPoints: raw['charters'] as int,
          developments: {
            for (var i = 0; i < StrategyDeck.values.length; i++)
              StrategyDeck.values[i]: (raw['developments'] as List)[i] as int,
          },
          cards: [
            for (final c in raw['cards'] as List)
              HeldCard(
                StrategyDeck.values.byName((c as List)[0] as String),
                c[1] as int,
              ),
          ],
        ),
    ];
    final sites = <int, Site>{
      for (final raw in list('sites'))
        (raw as List)[0] as int: Site(
          raw[1] as int,
          Structure.values.byName(raw[2] as String),
        ),
    };
    final players = [
      for (var i = 0; i < initialPlayers.length; i++)
        initialPlayers[i].copyWith(
          buildings: [
            for (final site in sites.values)
              if (site.owner == i) site.structure,
          ],
        ),
    ];
    final tacticalData = data['tactical'] as List?;
    final tactical = tacticalData == null
        ? null
        : TacticalWindow(
            tacticalData[0] as int,
            TacticalKind.values.byName(tacticalData[1] as String),
            tacticalData[2] as int,
            (tacticalData[3] as List).cast<int>(),
            bandit: tacticalData[4] == null
                ? null
                : eventFromJson(
                    Map<String, dynamic>.from(tacticalData[4] as Map),
                  ) as MoveBandit,
            card: tacticalData[5] == null
                ? null
                : eventFromJson(
                    Map<String, dynamic>.from(tacticalData[5] as Map),
                  ) as PlayStrategyCard,
          );
    return MatchState(
      seed: 0,
      board: board,
      topology: BoardTopology(board),
      players: players,
      sites: sites,
      roads: {
        for (final r in list('roads')) (r as List)[0] as int: r[1] as int,
      },
      bank: {
        for (var i = 0; i < Resource.values.length; i++)
          Resource.values[i]: list('bank')[i] as int,
      },
      phase: MatchPhase.values.byName(data['phase'] as String),
      active: number('active'),
      setupStep: number('step'),
      pendingVillage: data['pending'] as int?,
      dice: data['dice'] as int?,
      rollCount: number('rollCount'),
      banditTile: number('bandit'),
      round: number('round'),
      longestRoadHolder: data['holder'] as int?,
      knights: {
        for (final k in list('knights'))
          (k as List)[0] as int: KnightPiece(
            k[1] as int,
            KnightRank.values.byName(k[2] as String),
            k[3] as bool,
            k[4] as int,
          ),
      },
      fortified: list('forts').cast<int>().toSet(),
      reaverScars: list('scars').cast<int>().toSet(),
      dryRolls: {
        for (var i = 0; i < players.length; i++) i: list('dryRolls')[i] as int,
      },
      reliefUsed: list('reliefUsed').cast<int>().toSet(),
      reaverPressure: number('pressure'),
      invasions: number('invasions'),
      turnSerial: number('serial'),
      firstCapitalOwner: data['firstCapital'] as int?,
      lastInvasion: data['lastInvasion'] as String,
      lastCardEvent: data['lastCardEvent'] as String,
      catchupUsed: list('catchup').cast<int>().toSet(),
      offers: [
        for (final o in list('offers'))
          TradeProposal(
            (o as List)[0] as int,
            o[1] as int,
            o[2] as int,
            Resource.values.byName(o[3] as String),
            o[4] as int,
            Resource.values.byName(o[5] as String),
            o[6] as int,
            isCounter: o[7] as bool,
          ),
      ],
      tactical: tactical,
      reactionsUsed: list('reactionsUsed').cast<int>().toSet(),
      invasionAid: number('invasionAid'),
    );
  }

  static MatchEvent eventFromJson(Map<String, dynamic> e) {
    Resource good(String key) => Resource.values.byName(e[key] as String);
    int intAt(String key) => e[key] as int;
    return switch (e['type']) {
      'village' => PlaceVillage(intAt('vertex')),
      'road' => PlaceRoad(intAt('edge')),
      'upgrade' => UpgradeSite(intAt('vertex')),
      'roll' => RollDice(intAt('first'), intAt('second')),
      'bandit' => MoveBandit(intAt('tile'), victim: e['victim'] as int?),
      'bank' => BankExchange(good('give'), good('receive')),
      'offer' => ProposeTrade(
        intAt('target'),
        good('give'),
        intAt('giveCount'),
        good('want'),
        intAt('wantCount'),
        counterOf: e['counterOf'] as int?,
      ),
      'answer' => RespondTrade(
        intAt('player'),
        e['accept'] as bool,
        offerId: e['offerId'] as int?,
      ),
      'withdraw' => WithdrawTrade(intAt('offerId')),
      'tactical' => RespondTactical(
        intAt('windowId'),
        intAt('player'),
        TacticalChoice.values.byName(e['choice'] as String),
        cardIndex: e['cardIndex'] as int?,
        good: e['good'] == null ? null : good('good'),
      ),
      'tacticalTimeout' => TimeoutTactical(intAt('windowId'), intAt('player')),
      'develop' => DevelopTown(
        StrategyDeck.values.byName(e['track'] as String),
      ),
      'fortify' => FortifyTown(intAt('vertex')),
      'recruit' => RecruitKnight(intAt('vertex')),
      'activate' => ActivateKnight(intAt('vertex')),
      'promote' => PromoteKnight(intAt('vertex')),
      'knightMove' => MoveKnight(intAt('from'), intAt('to')),
      'invasion' => const ResolveInvasion(),
      'cardPlay' => PlayStrategyCard(
        intAt('hand'),
        vertex: e['vertex'] as int?,
        tile: e['tile'] as int?,
        target: e['target'] as int?,
        give: e['give'] == null ? null : good('give'),
        receive: e['receive'] == null ? null : good('receive'),
      ),
      'cardDiscard' => DiscardStrategyCard(intAt('hand')),
      'end' => const EndTurn(),
      _ => throw const FormatException('Unknown room event.'),
    };
  }
}
