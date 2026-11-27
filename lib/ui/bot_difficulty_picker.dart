import 'package:flutter/material.dart';

import '../engine/heuristic_ai.dart';

/// A single difficulty applies to every computer seat in the room.
class BotDifficultyPicker extends StatelessWidget {
  const BotDifficultyPicker({
    super.key,
    required this.difficulty,
    this.onChanged,
  });
  final BotDifficulty difficulty;
  final ValueChanged<BotDifficulty>? onChanged;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text('Bot difficulty'),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final level in BotDifficulty.values)
            ChoiceChip(
              label: Text(level.label),
              selected: difficulty == level,
              onSelected: onChanged == null ? null : (_) => onChanged!(level),
            ),
        ],
      ),
    ],
  );
}
