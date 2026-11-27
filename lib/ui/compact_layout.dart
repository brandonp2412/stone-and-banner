import 'package:flutter/material.dart';

/// Phone-landscape layouts have much less height than a portrait phone.
bool isCompactLandscape(BuildContext context) {
  final size = MediaQuery.sizeOf(context);
  return size.width > size.height && size.height <= 520 && size.width < 1050;
}

/// Preserve readable dialog text and full-sized controls while reclaiming
/// vertical space around them. Long bodies scroll; actions remain accessible.
class CompactAlertDialog extends StatelessWidget {
  const CompactAlertDialog({
    super.key,
    this.title,
    this.content,
    this.actions,
    this.scrollable = false,
    this.insetPadding,
    this.titlePadding,
    this.contentPadding,
    this.actionsPadding,
  });

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;
  final bool scrollable;
  final EdgeInsets? insetPadding;
  final EdgeInsetsGeometry? titlePadding;
  final EdgeInsetsGeometry? contentPadding;
  final EdgeInsetsGeometry? actionsPadding;

  @override
  Widget build(BuildContext context) {
    final compact = isCompactLandscape(context);
    return AlertDialog(
      title: title,
      content: content,
      actions: actions,
      scrollable: scrollable || compact,
      insetPadding: compact
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
          : insetPadding,
      titlePadding: compact
          ? const EdgeInsets.fromLTRB(16, 8, 16, 2)
          : titlePadding,
      contentPadding: compact
          ? const EdgeInsets.fromLTRB(16, 2, 16, 4)
          : contentPadding,
      actionsPadding: compact
          ? const EdgeInsets.fromLTRB(8, 0, 8, 6)
          : actionsPadding,
      titleTextStyle: compact ? Theme.of(context).textTheme.titleMedium : null,
      buttonPadding: compact ? const EdgeInsets.symmetric(horizontal: 3) : null,
    );
  }
}

/// One compact, consistent Back affordance for full-screen pushed pages.
class CompactPageHeader extends StatelessWidget {
  const CompactPageHeader({
    super.key,
    required this.title,
    required this.onBack,
    this.backTooltip = 'Back',
    this.actions = const [],
  });

  final String title;
  final VoidCallback onBack;
  final String backTooltip;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final compact = isCompactLandscape(context);
    return SizedBox(
      height: compact ? 38 : 52,
      child: Row(
        children: [
          IconButton(
            tooltip: backTooltip,
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back),
            constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
            padding: EdgeInsets.zero,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: compact
                  ? Theme.of(context).textTheme.titleMedium
                  : Theme.of(context).textTheme.titleLarge,
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// Use the actual panel width, not the screen width: desktop sidebars and
/// portrait phones stay single-column, wide landscape pages use spare space.
class AdaptiveActionGrid extends StatelessWidget {
  const AdaptiveActionGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      const gap = 8.0;
      final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
      final minWidth = 280 * scale;
      final columns = ((constraints.maxWidth + gap) / (minWidth + gap))
          .floor()
          .clamp(1, 3);
      final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        children: [
          for (final child in children) SizedBox(width: width, child: child),
        ],
      );
    },
  );
}

/// Short independent actions should size to their content and wrap only when
/// the available panel width cannot fit them side by side.
class AdaptiveActionRow extends StatelessWidget {
  const AdaptiveActionRow({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final landscape =
          MediaQuery.orientationOf(context) == Orientation.landscape;
      return landscape && constraints.maxWidth >= 380
          ? Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 4,
              children: children,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            );
    },
  );
}
