import 'board.dart';
import 'game.dart';

enum CardPower {
  fixedGoods,
  chooseBasic,
  chooseCommodity,
  freeRoad,
  freeFort,
  swap,
  portSwap,
  leverageSwap,
  activate,
  promote,
  exhaust,
  moveBandit,
  seizeGood,
}

class StrategyCard {
  const StrategyCard(
    this.id,
    this.name,
    this.track,
    this.power,
    this.description, {
    this.copies = 2,
    this.amount = 1,
    this.goods = const {},
  });

  final String id, name, description;
  final StrategyDeck track;
  final CardPower power;
  final int copies, amount;
  final Map<Resource, int> goods;
}

class HeldCard {
  const HeldCard(this.track, this.index);
  final StrategyDeck track;
  final int index;

  StrategyCard get definition => StrategyCards.deck(track)[index];
}

abstract final class StrategyCards {
  static const handLimit = 4;
  static const definitions = <StrategyCard>[
    StrategyCard(
      'forecast',
      'Forecast',
      StrategyDeck.innovation,
      CardPower.chooseBasic,
      'Study the next harvest: claim one available basic good.',
    ),
    StrategyCard(
      'surveyor',
      'Surveyor',
      StrategyDeck.innovation,
      CardPower.freeRoad,
      'Lay one connected road without paying its building cost.',
    ),
    StrategyCard(
      'efficient-plans',
      'Efficient Plans',
      StrategyDeck.innovation,
      CardPower.fixedGoods,
      'Recover one wood and one brick from the bank.',
      goods: {Resource.wood: 1, Resource.brick: 1},
    ),
    StrategyCard(
      'public-health',
      'Public Health',
      StrategyDeck.innovation,
      CardPower.fixedGoods,
      'Distribute one wheat and one wool from shared stock.',
      goods: {Resource.wheat: 1, Resource.wool: 1},
    ),
    StrategyCard(
      'bountiful-harvest',
      'Bountiful Harvest',
      StrategyDeck.innovation,
      CardPower.chooseBasic,
      'Gather two of one basic good while stock lasts.',
      amount: 2,
    ),
    StrategyCard(
      'prospecting',
      'Prospecting',
      StrategyDeck.innovation,
      CardPower.fixedGoods,
      'Extract two ore from the bank.',
      goods: {Resource.ore: 2},
    ),
    StrategyCard(
      'fortification-plans',
      'Fortification Plans',
      StrategyDeck.innovation,
      CardPower.freeFort,
      'Reinforce one of your Towns or Capitals without cost.',
    ),
    StrategyCard(
      'master-smith',
      'Master Smith',
      StrategyDeck.innovation,
      CardPower.fixedGoods,
      'Reclaim one ore and one brick for construction.',
      goods: {Resource.ore: 1, Resource.brick: 1},
    ),
    StrategyCard(
      'chronicle',
      'Chronicle',
      StrategyDeck.innovation,
      CardPower.fixedGoods,
      'Collect one paper and one coin.',
      copies: 1,
      goods: {Resource.paper: 1, Resource.coin: 1},
    ),
    StrategyCard(
      'trailblazers',
      'Trailblazers',
      StrategyDeck.innovation,
      CardPower.freeRoad,
      'Extend your road network by one connected edge.',
      copies: 1,
    ),

    StrategyCard(
      'caravan-expedition',
      'Caravan Expedition',
      StrategyDeck.commerce,
      CardPower.chooseBasic,
      'Bring two of one basic good home from market.',
      amount: 2,
    ),
    StrategyCard(
      'open-routes',
      'Open Routes',
      StrategyDeck.commerce,
      CardPower.swap,
      'Exchange one of your goods for a different bank good.',
    ),
    StrategyCard(
      'port-exchange',
      'Port Exchange',
      StrategyDeck.commerce,
      CardPower.portSwap,
      'Exchange one commodity for two basic goods of one kind.',
    ),
    StrategyCard(
      'trade-leverage',
      'Trade Leverage',
      StrategyDeck.commerce,
      CardPower.leverageSwap,
      'Exchange two basic goods of one kind for one commodity.',
    ),
    StrategyCard(
      'resource-levy',
      'Resource Levy',
      StrategyDeck.commerce,
      CardPower.chooseBasic,
      'Collect one available basic good.',
    ),
    StrategyCard(
      'commodity-levy',
      'Commodity Levy',
      StrategyDeck.commerce,
      CardPower.chooseCommodity,
      'Collect one paper, cloth or coin from the bank.',
    ),
    StrategyCard(
      'market-festival',
      'Market Festival',
      StrategyDeck.commerce,
      CardPower.fixedGoods,
      'Receive one wheat and one wool.',
      goods: {Resource.wheat: 1, Resource.wool: 1},
    ),
    StrategyCard(
      'crossroads',
      'Crossroads',
      StrategyDeck.commerce,
      CardPower.fixedGoods,
      'Receive one wood and one brick.',
      goods: {Resource.wood: 1, Resource.brick: 1},
    ),
    StrategyCard(
      'ledger-house',
      'Ledger House',
      StrategyDeck.commerce,
      CardPower.fixedGoods,
      'Receive one cloth and one wheat.',
      goods: {Resource.cloth: 1, Resource.wheat: 1},
    ),

    StrategyCard(
      'marshal',
      'Marshal',
      StrategyDeck.governance,
      CardPower.activate,
      'Activate one rested friendly Knight at no cost.',
    ),
    StrategyCard(
      'founding-charter',
      'Founding Charter',
      StrategyDeck.governance,
      CardPower.fixedGoods,
      'Secure one coin and one brick for the frontier.',
      goods: {Resource.coin: 1, Resource.brick: 1},
    ),
    StrategyCard(
      'defection',
      'Defection',
      StrategyDeck.governance,
      CardPower.exhaust,
      'Stand down an opposing active Knight.',
    ),
    StrategyCard(
      'boundary-dispute',
      'Boundary Dispute',
      StrategyDeck.governance,
      CardPower.moveBandit,
      'Reassign the Bandit to any other tile without theft.',
    ),
    StrategyCard(
      'political-pressure',
      'Political Pressure',
      StrategyDeck.governance,
      CardPower.seizeGood,
      'Compel another player to surrender one chosen good.',
    ),
    StrategyCard(
      'supply-raid',
      'Supply Raid',
      StrategyDeck.governance,
      CardPower.seizeGood,
      'Intercept one good from a rival store.',
    ),
    StrategyCard(
      'informant',
      'Informant',
      StrategyDeck.governance,
      CardPower.chooseCommodity,
      'Procure one available commodity.',
    ),
    StrategyCard(
      'rally',
      'Rally',
      StrategyDeck.governance,
      CardPower.promote,
      'Promote an active friendly Knight without cost.',
    ),
    StrategyCard(
      'tribute',
      'Tribute',
      StrategyDeck.governance,
      CardPower.fixedGoods,
      'Claim one coin and one wood from stock.',
      goods: {Resource.coin: 1, Resource.wood: 1},
    ),
  ];

  static final Map<StrategyDeck, List<StrategyCard>> _decks = {
    for (final track in StrategyDeck.values)
      track: List.unmodifiable([
        for (final definition in definitions)
          if (definition.track == track)
            for (var i = 0; i < definition.copies; i++) definition,
      ]),
  };

  static List<StrategyCard> deck(StrategyDeck track) => _decks[track]!;
}
