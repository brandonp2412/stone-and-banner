import 'package:flutter/material.dart';

import 'game_colors.dart';

import '../engine/board.dart';
import 'labels.dart';
import 'resource_icon.dart';

/// Tap goods in the supply to move them into a bundle, or in the bundle to undo.
class ResourceTransfer extends StatelessWidget {
  const ResourceTransfer({
    super.key,
    required this.title,
    required this.selected,
    required this.onChanged,
    this.holdings,
    this.limit,
    this.accent = const Color(0xffe5c183),
  });

  final String title;
  final Map<Resource, int> selected;
  final Map<Resource, int>? holdings;
  final int? limit;
  final Color accent;
  final ValueChanged<Map<Resource, int>> onChanged;

  @override
  Widget build(BuildContext context) {
    final total = selected.values.fold(0, (a, b) => a + b);
    void change(Resource good, int delta) {
      final next = Map<Resource, int>.of(selected);
      final count = (next[good] ?? 0) + delta;
      if (count <= 0) {
        next.remove(good);
      } else {
        next[good] = count;
      }
      onChanged(next);
    }

    Widget chip(Resource good, int count, bool remove, bool enabled) =>
        ActionChip(
          key: ValueKey(
            'transfer-$title-${remove ? 'remove' : 'add'}-${good.name}',
          ),
          avatar: ResourceIcon(good, size: 24),
          label: Text('${good.displayName} ×$count'),
          tooltip: '${remove ? 'Return' : 'Add'} one ${good.displayName}',
          onPressed: enabled ? () => change(good, remove ? -1 : 1) : null,
          backgroundColor: remove
              ? gameColor(context, accent).withValues(alpha: .2)
              : gameColor(context, const Color(0xff2b4249)),
          side: BorderSide(
            color: remove
                ? gameColor(context, accent)
                : gameColor(context, const Color(0xff38535b)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: gameColor(context, const Color(0xff1e343d)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: gameColor(context, accent).withValues(alpha: .5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            title,
            style: TextStyle(
              color: gameColor(context, accent),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          const Text('Tap to add', style: TextStyle(fontSize: 11)),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final good in Resource.values)
                chip(
                  good,
                  holdings == null
                      ? 1
                      : ((holdings![good] ?? 0) - (selected[good] ?? 0)).clamp(
                          0,
                          999,
                        ),
                  false,
                  (limit == null || total < limit!) &&
                      (selected[good] ?? 0) <
                          (holdings?[good] ?? (holdings == null ? 99 : 0)),
                ),
            ],
          ),
          const Divider(),
          Text(
            'Selected · $total${limit == null ? '' : ' / $limit'} · tap to return',
            style: const TextStyle(fontSize: 11),
          ),
          const SizedBox(height: 4),
          AnimatedSize(
            duration: const Duration(milliseconds: 150),
            alignment: Alignment.topLeft,
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final good in Resource.values)
                  if ((selected[good] ?? 0) > 0)
                    chip(good, selected[good]!, true, true),
                if (total == 0)
                  const Padding(
                    padding: EdgeInsets.all(12),
                    child: Text('No resources selected'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
