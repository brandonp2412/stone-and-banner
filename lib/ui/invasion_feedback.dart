import 'package:flutter/material.dart';

import '../engine/match.dart';

/// Keep resolution visible even when the next turn or a bot moves immediately.
class InvasionFeedback extends StatefulWidget {
  const InvasionFeedback({super.key, required this.state});

  final MatchState state;

  @override
  State<InvasionFeedback> createState() => _InvasionFeedbackState();
}

class _InvasionFeedbackState extends State<InvasionFeedback> {
  @override
  void didUpdateWidget(covariant InvasionFeedback oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state.invasions <= oldWidget.state.invasions) return;
    final report = widget.state.lastInvasion;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Invasion resolved'),
          content: Text(report),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
