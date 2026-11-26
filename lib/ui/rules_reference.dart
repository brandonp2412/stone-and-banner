import '../engine/advanced.dart';
import '../engine/board.dart';
import '../engine/cards.dart';
import '../engine/game.dart';
import '../engine/match.dart';
import 'labels.dart';

typedef RuleEntry = ({String title, String text});
typedef RuleSection = ({String title, List<RuleEntry> entries});

String _cost(Map<Resource, int> goods) => goods.entries
    .map((entry) => '${entry.value} ${entry.key.displayName}')
    .join(', ');

final List<RuleSection> rulesReference = [
  (
    title: 'Setup and turn order',
    entries: [
      (
        title: 'Your first two placements',
        text:
            'Stone & Banner is played with 3–6 players. Place a free Village '
            'at an empty junction, then a free Road along one of its sides. '
            'Leave at least one empty junction between buildings, including '
            'rival buildings. The last player in the first pass goes first '
            'in the second pass, and the order reverses. This time you place '
            'a free Town and an adjoining Road. The Town collects one basic '
            'good from each bordering productive tile, subject to bank stock.',
      ),
      (
        title: 'What you can do on your turn',
        text:
            'After setup, play starts with the first player in turn order. '
            'Roll once. Resolve any discards and Bandit move before taking '
            'actions. Then build, trade, develop, manage Guards or play '
            'Strategy Cards in any order as long as you can pay and have '
            'legal targets. End Turn passes play to the next seat. A round '
            'ends when every seat has taken a turn.',
      ),
    ],
  ),
  (
    title: 'Renown and winning',
    entries: [
      (
        title: 'How to score',
        text:
            'The match ends as soon as a player reaches '
            '${GameEngine.winningPoints} Renown. A Village is worth 1, a Town '
            '2 and a Capital 4. Upgrading replaces the old building value. '
            'The first player to build a Capital also earns a permanent '
            'Charter Point worth 1 Renown. Guardian’s Honour earned from '
            'defending the realm is worth 1 Renown per award.',
      ),
      (
        title: 'Crown Road (longest road)',
        text:
            'The longest continuous route of at least five Roads is worth '
            '2 Renown. A route can visit a junction again but can use each '
            'Road only once. Rival buildings and Guards interrupt the route. '
            'The current holder keeps the bonus on a tie for longest. If '
            'the holder drops out of the tie, nobody gets it until there is '
            'a sole leader.',
      ),
    ],
  ),
  (
    title: 'Dice, harvests and goods',
    entries: [
      (
        title: 'What each terrain produces',
        text: [
          for (final land in Land.values)
            if (land.produces case final good?)
              '${terrainLabel(land)} yields ${good.displayName}.',
          'Barren tiles yield nothing.',
        ].join(' '),
      ),
      (
        title: 'Collecting a harvest',
        text:
            'Add the two numbered dice. On a roll other than seven, every '
            'matching tile pays all bordering buildings, including those '
            'owned by players whose turn it isn’t. Each tile pays 1 good to '
            'a Village, 2 to a Town and 3 to a Capital. A tile occupied by '
            'the Bandit pays nothing. The bank starts with '
            '${MatchEngine.bankSupply} of each good. If it cannot cover all '
            'claims for a good on that roll, nobody receives that good.',
      ),
      (
        title: 'Paper, cloth and coin',
        text:
            'Developments convert part of a Town or Capital’s harvest into '
            'commodities. Innovation turns wood into paper, Commerce turns '
            'sheep into cloth and Governance turns ore into coin. Each '
            'matching tile converts 1 good per qualifying building at tiers '
            '1–4, or 2 at tier 5. Villages always produce basic goods.',
      ),
      (
        title: 'Relief after dry rolls',
        text:
            'If you are at least 3 Renown behind the leader and receive '
            'nothing on three consecutive harvest rolls, you get 1 wheat '
            'if the bank has stock. The relief allowance refreshes every '
            'three rounds. Innovation can trigger relief sooner and change '
            'which good you get.',
      ),
    ],
  ),
  (
    title: 'Rolling seven and the Bandit',
    entries: [
      (
        title: 'Discarding goods',
        text:
            'A seven skips the harvest. Every player over their safe hand '
            'size must return half their goods to the bank, rounded down. '
            'Count both basic goods and commodities. The base safe size '
            'is 7, plus 2 per fortified building, 2 at Commerce tier 3 and '
            '2 at Governance tier 3. The bonuses stack. Strategy Cards '
            'have a separate hand limit.',
      ),
      (
        title: 'Moving the Bandit and stealing',
        text:
            'Once discards are settled, move the Bandit to a different tile. '
            'It blocks that tile’s harvests until it moves again. If any '
            'rivals with goods have buildings on the tile and have built '
            'since setup, choose one to rob. You take one random good from '
            'their hand unless they intercept the theft.',
      ),
    ],
  ),
  (
    title: 'Building and upgrading',
    entries: [
      (
        title: 'Road',
        text:
            'Costs ${_cost(MatchEngine.roadCost)}, or 1 wood with '
            'Stoneworks. Build on an empty side adjoining your building or '
            'Road network. A rival building or Guard prevents you from '
            'extending through its junction. You can own up to '
            '${MatchEngine.roadLimit} Roads.',
      ),
      (
        title: 'Village',
        text:
            'Costs ${_cost(MatchEngine.villageCost)}. Build at an empty '
            'junction on one of your Roads, with no building at any '
            'neighbouring junction. A Guard occupies its junction.',
      ),
      (
        title: 'Town',
        text:
            'Upgrade your Village for ${_cost(MatchEngine.townCost)}. If '
            'the Reavers reduced that Town to a Village, rebuilding costs '
            '${_cost(MatchEngine.rebuildCost)}.',
      ),
      (
        title: 'Capital',
        text:
            'Upgrade your Town for ${_cost(MatchEngine.capitalCost)}. '
            'Paper, cloth and coin can be produced through developments '
            'or acquired in trades.',
      ),
      (
        title: 'Fortification',
        text:
            'Fortify your Town or Capital for ${_cost(MatchEngine.fortCost)}. '
            'Each fort adds 1 to the realm’s defence and adds 2 to your '
            'safe hand size. If the Reavers attack that junction, they '
            'destroy the fort and spare both your building and your goods.',
      ),
    ],
  ),
  (
    title: 'Trading and docks',
    entries: [
      (
        title: 'Bank exchange',
        text:
            'After rolling, give four of one good for one different good '
            'the bank has in stock (4:1). A building on either end of a '
            'general dock gives you 3:1. A specialised dock offers 2:1 '
            'when you give its pictured good. Commerce can lower the '
            'rate or increase what you receive. The best available rate '
            'applies. If you trail the leader by 3 or more Renown, a '
            'discounted 3:1 exchange is available once per round. A '
            'discounted dock exchange can use up that allowance.',
      ),
      (
        title: 'Offers, counteroffers and expiry',
        text:
            'Use Trade to offer a bundle of goods in exchange for another '
            'bundle. Offer to one rival or open the offer to everyone. '
            'Eligible players can accept or decline, or propose different '
            'terms. An open offer goes to the first player to accept. '
            'Both sides must still have the goods when the trade settles. '
            'You can answer on your own turn or while the proposer is '
            'taking actions. Offers expire when the proposer’s next turn '
            'begins, and the proposer can withdraw an offer on their turn.',
      ),
    ],
  ),
  (
    title: 'Town developments',
    entries: [
      (
        title: 'Unlocking a track',
        text:
            'Open Realm to develop Innovation, Commerce or Governance. '
            'You must own a Town or Capital next to the track’s terrain. '
            'Developments belong to you and apply across your realm. '
            'Buy tiers in order. Tier 1 costs 1 wheat and 1 ore. Tiers '
            '2–5 each cost 1 wheat, 2 ore and one fewer commodity than '
            'the tier number. Reaching a higher tier keeps the earlier '
            'benefits except where it improves the same effect.',
      ),
      (
        title: 'Innovation (Woodland and paper)',
        text:
            '1. Scriptorium converts wood into paper.\n'
            '2. Stoneworks drops the brick cost of building Roads.\n'
            '3. Reservoir triggers relief after two dry rolls.\n'
            '4. Supply Network gives your least stocked available basic '
            'good as relief.\n'
            '5. Observatory converts two wood into paper per harvest '
            'and adds 1 realm defence.',
      ),
      (
        title: 'Commerce (Sheep Pastures and cloth)',
        text:
            '1. Loomhouse converts sheep into cloth.\n'
            '2. Market Hall opens 3:1 bank exchanges.\n'
            '3. Trade Wharf gives 2 cloth when you exchange for cloth '
            'at the bank and raises your safe hand size by 2.\n'
            '4. Guild Exchange opens 2:1 bank exchanges.\n'
            '5. Grand Bazaar gives 2 goods in every bank exchange and '
            'converts two sheep into cloth per harvest.',
      ),
      (
        title: 'Governance (Ore Hills and coin)',
        text:
            '1. Mint House converts ore into coin.\n'
            '2. Watchtower adds 1 realm defence.\n'
            '3. Fortifications raises your safe hand size by 2 and '
            'protects your goods from Reaver looting.\n'
            '4. Marshal’s Hall removes the ore cost of recruiting Guards.\n'
            '5. High Council adds another 1 realm defence and converts '
            'two ore into coin per harvest.',
      ),
    ],
  ),
  (
    title: 'Guards',
    entries: [
      (
        title: 'Recruit and activate',
        text:
            'Recruit a Sentinel at an empty junction on one of your Roads '
            'for ${_cost(MatchEngine.recruitCost)}, or 1 sheep with Marshal’s '
            'Hall. You can have up to three Guards. A recruit starts '
            'inactive. On a later turn, pay ${_cost(MatchEngine.activateCost)} '
            'to activate it. Only active Guards add to the realm’s defence.',
      ),
      (
        title: 'Promote, move and displace',
        text:
            'Sentinels add 1 defence, Wardens 2 and Champions 3. Promote an '
            'active Sentinel to Warden for '
            '${_cost(MatchEngine.promotionCost(GuardRank.sentinel))}, or a '
            'Warden to Champion for '
            '${_cost(MatchEngine.promotionCost(GuardRank.warden))}. An active '
            'Guard can instead move one junction along your Road. It can '
            'displace a weaker rival Guard, which retreats along one of '
            'its Roads and becomes inactive. If it has nowhere to retreat, '
            'it is removed. A Guard can move or promote once per turn.',
      ),
    ],
  ),
  (
    title: 'Reaver Fleet and invasions',
    entries: [
      (
        title: 'When the fleet attacks',
        text:
            'Fleet pressure rises by one each round. In a new match an '
            'invasion occurs after six rounds, before the first player '
            'rolls. With only Villages on the board, there is no damage '
            'and no Honour. Otherwise the fleet has 1 strength per Town '
            'or Capital across the board, plus 1 on raids after the first.',
      ),
      (
        title: 'Defending and earning Guardian’s Honour',
        text:
            'Everyone defends together. Add the strength of all active '
            'Guards, 1 per fort, bonuses from Watchtower, High Council '
            'and Observatory, and any emergency aid. Meeting the fleet’s '
            'strength is enough. On a successful defence the player who '
            'contributed the most active Guard strength earns 1 Guardian’s '
            'Honour, up to 2 total. Ties and defences with no active '
            'Guards award no Honour.',
      ),
      (
        title: 'What happens if the defence fails',
        text:
            'The fleet targets the highest-scoring player with a Town '
            'or Capital. Ties are settled by the lowest eligible junction '
            'number. A fort there is destroyed in place of the building. '
            'Otherwise a Capital becomes a Town or a Town becomes a '
            'Village, and the owner loses up to two goods from their '
            'most plentiful stacks unless they have Governance tier 3. '
            'After the raid, Guards become inactive and fleet pressure '
            'and emergency aid reset.',
      ),
    ],
  ),
  (
    title: 'Tactical reactions',
    entries: const [
      (
        title: 'Intercepting theft',
        text:
            'If the Bandit targets you, an active Guard on a corner of '
            'the chosen tile can intercept. The Guard becomes inactive '
            'and you keep your goods. The Bandit still moves.',
      ),
      (
        title: 'Countering a Strategy Card',
        text:
            'Play Boundary Dispute in response to a card that seizes one '
            'of your goods, or Defection in response to a card targeting '
            'one of your Guards for exhaustion. Both cards are spent '
            'when you counter.',
      ),
      (
        title: 'Pledging emergency aid',
        text:
            'When the fleet is ahead by 1 or 2 strength, eligible players '
            'can pledge 1 wheat for 1 defence or 1 ore for 2 defence. '
            'The realm can gain at most 2 strength from aid in a raid. '
            'Invitations stop once the defence can hold. Passing keeps '
            'your goods. You may use one tactical reaction per round, '
            'shared across interceptions, counters and aid.',
      ),
    ],
  ),
  (
    title: 'Strategy Cards',
    entries: [
      (
        title: 'Drawing and playing cards',
        text:
            'Every roll also checks for a Strategy Card draw. The event '
            'die selects Innovation, Commerce or Governance on 1, 2 or 3. '
            'On 4–6 no cards are drawn. The tier die gives the minimum '
            'tier in that track needed to draw. All eligible players can '
            'draw one card in turn order, starting with the roller, up '
            'to a hand limit of ${StrategyCards.handLimit}. When a deck '
            'runs out, its discards are shuffled back in. Open your '
            'Strategy Hand after rolling to play a card and choose any '
            'required target, or discard it to make room for later draws.',
      ),
    ],
  ),
  for (final track in StrategyDeck.values)
    (
      title: '${track.name[0].toUpperCase()}${track.name.substring(1)} cards',
      entries: [
        for (final card in [
          ...StrategyCards.definitions,
          ...StrategyCards.extraDefinitions,
        ])
          if (card.track == track) (title: card.name, text: card.description),
      ],
    ),
];
