import 'package:flutter/material.dart';

import '../engine/match.dart';

/// Fleet approach and shared defence, including pledged emergency aid.
class InvasionMeter extends StatelessWidget {
  const InvasionMeter({super.key, required this.state});

  final MatchState state;

  @override
  Widget build(BuildContext context) {
    final pressure = state.reaverPressure.clamp(0, 3);
    final remaining = 3 - pressure;
    final arriving = state.phase == MatchPhase.invasion || remaining == 0;
    final arrival = arriving
        ? 'Invasion now'
        : 'Invasion in $remaining ${remaining == 1 ? 'round' : 'rounds'}';
    final fleetColor = arriving || remaining == 1
        ? const Color(0xffff977f)
        : const Color(0xffffd08a);
    final have = MatchEngine.defenceStrength(state) + state.invasionAid;
    final need = MatchEngine.invasionStrength(state);
    final ready = have >= need;
    final color = ready ? const Color(0xff40d5b4) : const Color(0xffffc477);
    final status = need == 0
        ? 'Villages are safe'
        : ready
        ? 'Ready to defend'
        : '${need - have} more needed';
    return Semantics(
      label:
          '$arrival. Fleet advances at the end of each round. Shared invasion defence: $have points available, $need required. $status.',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Reserve the tallest countdown at the available width and scale.
          Stack(
            children: [
              for (final label in {
                arrival,
                'Invasion in 3 rounds',
                'Invasion in 1 round',
                'Invasion now',
              })
                Visibility(
                  visible: label == arrival,
                  maintainSize: true,
                  maintainAnimation: true,
                  maintainState: true,
                  child: Text(
                    label,
                    style: TextStyle(
                      color: fleetColor,
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Defence $have / $need',
            style: TextStyle(fontSize: 11, color: color),
          ),
        ],
      ),
    );
  }
}
