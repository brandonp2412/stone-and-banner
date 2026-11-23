import 'package:flutter/material.dart';

import 'game_colors.dart';

import '../engine/board.dart';
import 'labels.dart';
import 'resource_icon.dart';

/// One stable row per resource, with both sides of the trade visible together.
class TradePicker extends StatelessWidget {
  const TradePicker({
    super.key,
    required this.holdings,
    required this.gives,
    required this.wants,
    required this.onChange,
    this.bank = false,
    this.bankStock = const {},
    this.rates = const {},
    this.receipts = const {},
  });

  final Map<Resource, int> holdings, gives, wants, bankStock, rates, receipts;
  final bool bank;
  final void Function(Resource good, bool giving, int delta) onChange;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).height < 500;
    final gold = gameColor(context, const Color(0xffe5c183));
    final mint = gameColor(context, const Color(0xff73d9c0));
    Widget quantity(Resource good, bool giving) {
      final count = (giving ? gives : wants)[good] ?? 0;
      final step = bank ? (giving ? rates[good] : receipts[good]) ?? 1 : 1;
      final cap = giving
          ? holdings[good] ?? 0
          : bank
          ? bankStock[good] ?? 0
          : 99;
      final opposite = (giving ? wants : gives)[good] ?? 0;
      final enabled = bank
          ? cap >= step && opposite == 0
          : count < cap && opposite == 0;
      final color = giving ? gold : mint;
      final label = giving ? 'Give' : 'Get';
      return Container(
        width: 100,
        height: compact ? 34 : 42,
        decoration: BoxDecoration(
          color: count > 0
              ? color.withValues(alpha: .18)
              : gameColor(context, const Color(0xff192b32)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: count > 0
                ? color
                : gameColor(context, const Color(0xff3a4c53)),
          ),
        ),
        child: Row(
          children: [
            if (!bank && count > 0)
              SizedBox(
                width: 30,
                child: IconButton(
                  key: ValueKey(
                    'trade-${giving ? 'give' : 'get'}-minus-${good.name}',
                  ),
                  tooltip:
                      'Remove one ${good.displayName} from ${giving ? 'offer' : 'request'}',
                  padding: EdgeInsets.zero,
                  onPressed: () => onChange(good, giving, -1),
                  icon: Icon(Icons.remove, size: 16, color: color),
                ),
              ),
            Expanded(
              child: Semantics(
                label: '$label ${good.displayName}, $count selected',
                button: true,
                child: InkWell(
                  key: ValueKey(
                    'trade-${giving ? 'give' : 'get'}-${good.name}',
                  ),
                  borderRadius: BorderRadius.circular(10),
                  onTap: enabled ? () => onChange(good, giving, 1) : null,
                  child: Center(
                    child: Text(
                      count > 0
                          ? '$count${bank ? '' : '  +'}'
                          : bank
                          ? '$step'
                          : '+',
                      style: TextStyle(
                        color: enabled || count > 0
                            ? color
                            : gameColor(context, const Color(0xff63737a)),
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    Widget row(Resource good) => Padding(
      padding: EdgeInsets.symmetric(vertical: compact ? 0 : 3),
      child: Row(
        children: [
          ResourceIcon(good, size: 26),
          const SizedBox(width: 7),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  good.displayName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${holdings[good] ?? 0} in hand',
                  style: TextStyle(
                    fontSize: 10,
                    color: gameColor(context, const Color(0xffa8b9bd)),
                  ),
                ),
              ],
            ),
          ),
          quantity(good, true),
          const SizedBox(width: 6),
          quantity(good, false),
        ],
      ),
    );
    Widget column(List<Resource> goods) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'RESOURCE',
                style: TextStyle(
                  fontSize: 10,
                  color: gameColor(context, const Color(0xffa8b9bd)),
                ),
              ),
            ),
            SizedBox(
              width: 100,
              child: Center(
                child: Text(
                  'YOU GIVE',
                  style: TextStyle(
                    fontSize: 11,
                    color: gold,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            SizedBox(width: 6),
            SizedBox(
              width: 100,
              child: Center(
                child: Text(
                  'YOU GET',
                  style: TextStyle(
                    fontSize: 11,
                    color: mint,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final good in goods) row(good),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 660) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: column(Resource.values.take(4).toList())),
              const SizedBox(width: 16),
              Expanded(child: column(Resource.values.skip(4).toList())),
            ],
          );
        }
        return column(Resource.values);
      },
    );
  }
}
