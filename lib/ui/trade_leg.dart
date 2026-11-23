import 'labels.dart';

import 'package:flutter/material.dart';

import '../engine/board.dart';
import 'resource_icon.dart';

/// Mobile-first resource and quantity picker for offers and bank exchanges.
class TradeLeg extends StatelessWidget {
  const TradeLeg({
    super.key,
    required this.title,
    required this.hint,
    required this.resource,
    required this.count,
    required this.onResource,
    required this.onCount,
    this.available,
    this.holdings,
    this.showCount = true,
    this.highlight = false,
    this.compact = false,
  });

  final String title, hint;
  final Resource resource;
  final int count;
  final int? available;
  final Map<Resource, int>? holdings;
  final bool showCount, highlight, compact;
  final ValueChanged<Resource> onResource;
  final ValueChanged<int> onCount;

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xffe5c183);
    const cyan = Color(0xff73d9c0);
    final accent = highlight ? cyan : gold;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xff1e343d),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withValues(alpha: .5)),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: accent,
              fontSize: 11,
              letterSpacing: 1.1,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            hint,
            style: const TextStyle(color: Color(0xffaec5c9), fontSize: 11),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 5,
            runSpacing: 4,
            children: [
              for (final good in Resource.values)
                ChoiceChip(
                  key: ValueKey(
                    'trade-good-${title.toLowerCase()}-${good.displayName}',
                  ),
                  showCheckmark: false,
                  avatar: ResourceIcon(good, size: 24),
                  selected: good == resource,
                  label: Text(
                    holdings == null
                        ? good.displayName
                        : '${good.displayName} (${holdings![good] ?? 0})',
                  ),
                  labelStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: good == resource
                        ? FontWeight.w800
                        : FontWeight.w500,
                    color: good == resource
                        ? const Color(0xff182b32)
                        : const Color(0xffc6d7d9),
                  ),
                  backgroundColor: const Color(0xff2b4249),
                  selectedColor: accent,
                  side: BorderSide(
                    color: good == resource ? accent : const Color(0xff38535b),
                  ),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  onSelected: (_) => onResource(good),
                ),
            ],
          ),
          if (showCount) ...[
            const SizedBox(height: 9),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Quantity',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Decrease quantity',
                  onPressed: count > 1 ? () => onCount(count - 1) : null,
                  icon: const Icon(Icons.remove, size: 18),
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Increase quantity',
                  onPressed: count < 99 ? () => onCount(count + 1) : null,
                  icon: const Icon(Icons.add, size: 18),
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ] else ...[
            const SizedBox(height: 7),
            Text(
              'Quantity: $count',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ],
          if (available != null) ...[
            const SizedBox(height: 5),
            Text(
              'Available: $available',
              style: const TextStyle(color: Color(0xffaec5c9), fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }
}
