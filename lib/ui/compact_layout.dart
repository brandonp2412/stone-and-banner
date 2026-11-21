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
  });

  final String title;
  final VoidCallback onBack;
  final String backTooltip;

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
        ],
      ),
    );
  }
}
