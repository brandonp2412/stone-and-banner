import 'package:flutter/material.dart';

import '../engine/board.dart';
import 'labels.dart';
import 'resource_icon.dart';

/// Quantified resources in compact UI labels, not free-form board/rules text.
/// The full original label remains the screen-reader label in either mode.
class ResourceLabel extends StatelessWidget {
  const ResourceLabel(
    this.text, {
    super.key,
    this.style,
    this.adaptive = false,
    this.showNames = false,
  });

  final String text;
  final TextStyle? style;
  final bool adaptive;
  final bool showNames;

  static final _amount = RegExp(
    r'([0-9]+)\s+(wood|brick|wheat|sheep|wool|ore|paper|cloth|coin)\b',
    caseSensitive: false,
  );

  @override
  Widget build(BuildContext context) {
    final effective = DefaultTextStyle.of(context).style.merge(style);
    final size = (effective.fontSize ?? 14) + 3;
    final matches = _amount.allMatches(text).toList();
    if (matches.isEmpty) return Text(text, style: style);

    Widget render(bool names) {
      final spans = <InlineSpan>[];
      var offset = 0;
      for (final match in matches) {
        spans.add(TextSpan(text: text.substring(offset, match.start)));
        final good = Resource.values.firstWhere(
          (r) =>
              r.displayName == match[2]!.toLowerCase() ||
              r.name == match[2]!.toLowerCase(),
        );
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  match[1]!,
                  style: effective,
                  textScaler: TextScaler.noScaling,
                ),
                const SizedBox(width: 3),
                ResourceIcon(good, size: size),
                if (names) ...[
                  const SizedBox(width: 3),
                  Text(
                    good.displayName,
                    style: effective,
                    textScaler: TextScaler.noScaling,
                  ),
                ],
              ],
            ),
          ),
        );
        offset = match.end;
      }
      spans.add(TextSpan(text: text.substring(offset)));
      return Text.rich(
        TextSpan(children: spans),
        style: style,
        semanticsLabel: text,
      );
    }

    if (!adaptive) return render(showNames);
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaler = MediaQuery.textScalerOf(context);
        final scaledIcon =
            size *
            scaler.scale(effective.fontSize ?? 14) /
            (effective.fontSize ?? 14);
        // Require comfortable extra space on each line before adding names.
        final fits = text.split('\n').every((line) {
          final painter = TextPainter(
            text: TextSpan(text: line, style: effective),
            textDirection: Directionality.of(context),
            textScaler: scaler,
          )..layout();
          final width = painter.width;
          painter.dispose();
          return width +
                  _amount.allMatches(line).length * (scaledIcon + 6) +
                  20 <=
              constraints.maxWidth;
        });
        return render(fits);
      },
    );
  }
}
