import 'package:flutter/material.dart';

import '../engine/board.dart';
import '../engine/match.dart';
import 'trade_feedback.dart';

/// Outgoing and incoming offers live in one mobile-first trade stack.
class TradeMarket extends StatelessWidget {
  const TradeMarket({
    super.key,
    required this.state,
    required this.onBank,
    required this.onOffer,
    required this.onCounter,
    required this.onEvent,
    required this.viewerSeat,
    this.onReturnToBoard,
    this.allowOffers = true,
    this.computerSeats = const <int>{},
  });

  final MatchState state;
  final bool allowOffers;
  final Set<int> computerSeats;
  final VoidCallback onBank, onOffer;
  final ValueChanged<TradeProposal> onCounter;
  final ValueChanged<MatchEvent> onEvent;
  final int viewerSeat;
  final VoidCallback? onReturnToBoard;

  static const ink = Color(0xff172b33);
  static const border = Color(0xff37515a);
  static const gold = Color(0xffe5c183);

  @override
  Widget build(BuildContext context) {
    final ownTurn =
        allowOffers &&
        state.tactical == null &&
        state.phase == MatchPhase.actions &&
        state.active == viewerSeat;
    final hasOutgoing = state.offers.any((o) => o.proposer == viewerSeat);
    final incoming = state.offers
        .where((o) => o.canRespond(viewerSeat))
        .toList();
    final outgoing = state.offers
        .where((o) => o.proposer == viewerSeat)
        .toList();
    final feedback = latestTradeFeedback(state, viewer: viewerSeat);
    final lastVisibleResponse = state.events.reversed
        .whereType<RespondTrade>()
        .where(
          (reply) =>
              tradeFeedbackForResponse(state, reply, viewer: viewerSeat) !=
              null,
        )
        .firstOrNull;
    final acceptedTrade = lastVisibleResponse?.accept == true;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Primary actions must stay on the first visible row even in
        // 320px-high landscape and with large accessibility text.
        Row(
          children: [
            Expanded(
              child: FilledButton(
                key: const ValueKey('create-player-offer'),
                onPressed: ownTurn && !hasOutgoing ? onOffer : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  backgroundColor: gold,
                  foregroundColor: const Color(0xff1c2830),
                ),
                child: const Text(
                  'Player trade',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                onPressed: ownTurn ? onBank : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(44),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                child: const Text(
                  'Bank trade',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        if (ownTurn && incoming.isEmpty && outgoing.isEmpty) ...[
          const SizedBox(height: 8),
          const Text(
            'Bots consider offers immediately. Players can accept or counter offers.',
            style: TextStyle(color: Color(0xffacc4c9), fontSize: 12),
          ),
        ],
        if (hasOutgoing)
          Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              outgoing.any(
                    (o) =>
                        (o.target == -1 ||
                        computerSeats.isNotEmpty ||
                        computerSeats.contains(o.target)),
                  )
                  ? 'Thinking about your offer…'
                  : 'Your offer is awaiting a reply.',
              style: TextStyle(color: gold, fontSize: 12),
            ),
          ),
        if (!ownTurn)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Row(
              children: [
                const Icon(
                  Icons.lock_outline,
                  size: 20,
                  color: Color(0xffe5c183),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Roll or resolve the current event before trading.',
                    style: TextStyle(color: Color(0xffaec2c6), fontSize: 12),
                  ),
                ),
                if (onReturnToBoard != null)
                  OutlinedButton(
                    onPressed: onReturnToBoard,
                    child: const Text('Board'),
                  ),
              ],
            ),
          ),
        if (incoming.isNotEmpty) ...[
          const SizedBox(height: 9),
          _heading('NEEDS YOUR ANSWER', Icons.mark_email_unread_outlined),
          for (final offer in incoming)
            _offerCard(
              context,
              offer,
              incoming: true,
              enabled:
                  state.phase == MatchPhase.actions &&
                  state.tactical == null &&
                  (ownTurn || offer.proposer == state.active),
            ),
        ],
        if (outgoing.isNotEmpty) ...[
          const SizedBox(height: 9),
          _heading(
            outgoing.any(
                  (o) =>
                      (o.target == -1 ||
                      computerSeats.isNotEmpty ||
                      computerSeats.contains(o.target)),
                )
                ? 'CONSIDERING YOUR OFFER'
                : 'YOUR PENDING OFFER',
            Icons.schedule_outlined,
          ),
          for (final offer in outgoing)
            _offerCard(context, offer, incoming: false, enabled: ownTurn),
        ],
        if (feedback != null) ...[
          const SizedBox(height: 14),
          Container(
            key: const ValueKey('trade-result'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: acceptedTrade ? const Color(0xff153e36) : ink,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: acceptedTrade ? const Color(0xff6de0ae) : border,
                width: acceptedTrade ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  acceptedTrade
                      ? Icons.celebration_rounded
                      : Icons.receipt_long_outlined,
                  color: acceptedTrade ? const Color(0xff6de0ae) : gold,
                  size: 23,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    feedback,
                    style: const TextStyle(
                      color: Color(0xffdce8e9),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (incoming.isEmpty && outgoing.isEmpty) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: ink,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: border),
            ),
            child: const Column(
              children: [
                Icon(Icons.local_post_office_outlined, color: gold, size: 26),
                SizedBox(height: 6),
                Text(
                  'No offers on the table',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                SizedBox(height: 3),
                Text(
                  'Offer a trade. Goods change hands only if it is accepted.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xffadc4c6), fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _heading(String label, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      children: [
        Icon(icon, size: 15, color: gold),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: gold,
            letterSpacing: 1.2,
            fontSize: 10,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );

  Widget _offerCard(
    BuildContext context,
    TradeProposal offer, {
    required bool incoming,
    required bool enabled,
  }) {
    final counterAvailable =
        enabled &&
        allowOffers &&
        !state.offers.any((o) => o.proposer == viewerSeat);
    final canAccept =
        enabled &&
        canPayTrade(state.players[viewerSeat].stores, offer.wants) &&
        canPayTrade(state.players[offer.proposer].stores, offer.gives);
    return Card(
      key: ValueKey('trade-offer-${offer.id}'),
      margin: const EdgeInsets.only(bottom: 9),
      color: ink,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: BorderSide(color: incoming ? gold.withValues(alpha: .7) : border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  incoming
                      ? Icons.markunread_mailbox_outlined
                      : Icons.outbox_outlined,
                  size: 17,
                  color: gold,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    incoming
                        ? 'From ${state.players[offer.proposer].id}'
                        : offer.target == -1
                        ? 'To everyone · first acceptance wins'
                        : 'To ${state.players[offer.target].id}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (offer.isCounter)
                  const Text(
                    'COUNTER',
                    style: TextStyle(
                      fontSize: 9,
                      color: gold,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: _goods(
                    incoming ? 'YOU RECEIVE' : 'YOU GIVE',
                    offer.gives,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 5),
                  child: Icon(Icons.swap_horiz_rounded, color: gold, size: 23),
                ),
                Expanded(
                  child: _goods(incoming ? 'YOU GIVE' : 'YOU GET', offer.wants),
                ),
              ],
            ),
            const SizedBox(height: 5),
            if (incoming)
              Wrap(
                spacing: 7,
                runSpacing: 5,
                children: [
                  OutlinedButton(
                    key: ValueKey('decline-offer-${offer.id}'),
                    onPressed: enabled
                        ? () => onEvent(
                            RespondTrade(viewerSeat, false, offerId: offer.id),
                          )
                        : null,
                    child: const Text('Decline'),
                  ),
                  OutlinedButton(
                    key: ValueKey('counter-offer-${offer.id}'),
                    onPressed: counterAvailable ? () => onCounter(offer) : null,
                    child: const Text('Counter'),
                  ),
                  FilledButton(
                    key: ValueKey('accept-offer-${offer.id}'),
                    onPressed: canAccept
                        ? () => onEvent(
                            RespondTrade(viewerSeat, true, offerId: offer.id),
                          )
                        : null,
                    child: const Text('Accept'),
                  ),
                ],
              )
            else ...[
              const Text(
                'Your goods stay available until this trade is accepted.',
                style: TextStyle(color: Color(0xffb7c9ce), fontSize: 11),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: enabled
                      ? () => onEvent(WithdrawTrade(offer.id))
                      : null,
                  icon: const Icon(Icons.undo, size: 17),
                  label: const Text('Withdraw'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _goods(String label, Map<Resource, int> goods) => Container(
    constraints: const BoxConstraints(minHeight: 54),
    padding: const EdgeInsets.all(7),
    decoration: BoxDecoration(
      color: const Color(0xff223b41),
      borderRadius: BorderRadius.circular(11),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xffadbdc1),
            fontWeight: FontWeight.w700,
            letterSpacing: .6,
            fontSize: 9,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          tradeBundleText(goods),
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ],
    ),
  );
}
