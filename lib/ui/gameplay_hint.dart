/// First-use guidance, separate from the match rules and replay state.
class GameplayHint {
  const GameplayHint(this.id, this.title, this.explanation);
  final String id;
  final String title;
  final String explanation;
}

const gameplayHints = <String, GameplayHint>{
  'setupVillage': GameplayHint(
    'setupVillage',
    'Choose your starting settlement',
    'Tap a glowing junction to place your free settlement. Nearby terrain and number tokens determine which goods it can produce. Leave room for roads and future settlements.',
  ),
  'setupTown': GameplayHint(
    'setupTown',
    'Place your starting Town',
    'Your second starting settlement is a free Town. Choose its neighbouring terrain carefully, then connect a free road. Develop the Town in Realm to unlock advanced goods.',
  ),
  'setupRoad': GameplayHint(
    'setupRoad',
    'Connect your settlement',
    'Tap a glowing edge beside the settlement you just placed. This starting road is free. Extend roads later to reach new building sites.',
  ),
  'roll': GameplayHint(
    'roll',
    'Roll to start your turn',
    'Roll the dice to produce goods on matching terrain numbers. The event die can also advance the invasion or award strategy cards. Resolve the result before building or trading.',
  ),
  'bandit': GameplayHint(
    'bandit',
    'Move the Bandit',
    'Tap a different hex. The Bandit blocks production there. Choose a neighbouring rival for any available theft; responses resolve before normal actions resume.',
  ),
  'invasion': GameplayHint(
    'invasion',
    'Defend against the invasion',
    'Active Knights and Fortifications contribute to shared defence. Review the defence forecast before resolving the invasion. A failed defence can damage a leading Town or Capital.',
  ),
  'actions': GameplayHint(
    'actions',
    'Shape your realm',
    'Build roads and settlements, trade for missing goods, or play a strategy card. Select an action to see its cost and legal targets. End your turn when you are done.',
  ),
  'road': GameplayHint(
    'road',
    'Extend your roads',
    'Tap a glowing edge connected to your network. Roads open routes to new settlement sites. The action shows the current cost, including any discounts.',
  ),
  'village': GameplayHint(
    'village',
    'Build a village',
    'Tap a glowing junction along your road network. Settlements need space from other settlements. A new village produces goods from its neighbouring terrain.',
  ),
  'upgrade': GameplayHint(
    'upgrade',
    'Upgrade a settlement',
    'Tap a highlighted settlement to upgrade it. The action shows the required goods. Towns can be developed in Realm to unlock advanced production.',
  ),
  'fortify': GameplayHint(
    'fortify',
    'Fortify a Town',
    'Tap a highlighted Town to add a Fortification. Each Fortification adds 1 shared invasion defence and raises your safe hand limit by 2 goods when a seven is rolled. Check the displayed cost before building.',
  ),
  'recruit': GameplayHint(
    'recruit',
    'Recruit a Knight',
    'Tap a highlighted junction to recruit a Knight. Recruit where your network allows it, then activate the Knight so it can defend and take actions.',
  ),
  'activate': GameplayHint(
    'activate',
    'Activate a Knight',
    'Tap a highlighted Knight and pay the activation cost. Active Knights contribute to invasion defence and can perform Knight actions.',
  ),
  'promote': GameplayHint(
    'promote',
    'Promote a Knight',
    'Tap a highlighted Knight to increase its rank and strength. Higher ranks have different costs and requirements; the action lists the cost for each promotion.',
  ),
  'knightMove': GameplayHint(
    'knightMove',
    'Move an active Knight',
    'Select your Knight, then tap a glowing destination. Movement follows your road network. An active Knight can move once per turn.',
  ),
  'trade': GameplayHint(
    'trade',
    'Trade for what you need',
    'Exchange goods with the bank or propose a trade to a rival. Review what you give and receive before confirming. Rival offers can be accepted, declined or countered.',
  ),
  'cards': GameplayHint(
    'cards',
    'Use your strategy cards',
    'Select a card to read its effect and requirements before playing it. Some cards need a target or a response. Resolve those choices to continue your turn.',
  ),
  'realm': GameplayHint(
    'realm',
    'Develop your realm',
    'Use the development tracks to improve your Towns. Paper funds Innovation, cloth funds Commerce, and coin funds Governance. Each track shows its next cost and benefit.',
  ),
  'town': GameplayHint(
    'town',
    'Develop your Town',
    'Develop your Town in Realm to produce advanced goods.\n\nA Scriptorium, Loomhouse or Mint House costs 1 wheat + 1 ore. Collect paper, cloth or coin on matching rolls.',
  ),
  'response_bandit': GameplayHint(
    'response_bandit',
    'Respond to the Bandit',
    'Review the pending theft and your available responses. Use an eligible response or pass to let the action continue.',
  ),
  'response_governance': GameplayHint(
    'response_governance',
    'Respond to a strategy card',
    'Review the pending card effect. Choose an available counter or pass. The original action waits until responses are resolved.',
  ),
  'response_invasion': GameplayHint(
    'response_invasion',
    'Offer emergency defence',
    'Review the invasion and any available aid. Contribute if you can, or pass. The defence result is calculated after the responses finish.',
  ),
};
