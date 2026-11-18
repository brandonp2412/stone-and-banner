import 'package:flutter/material.dart';

/// A single visual language for non-turn alerts across the game.
class GameNotice {
  const GameNotice._();

  static SnackBar snackBar(
    String message, {
    bool error = false,
    Duration duration = const Duration(seconds: 3),
  }) {
    final accent = error ? const Color(0xffffa28e) : const Color(0xffe5c183);
    return SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xff18313a),
      elevation: 14,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: BorderSide(color: accent.withValues(alpha: .65)),
      ),
      duration: duration,
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            error ? Icons.error_outline_rounded : Icons.auto_awesome_rounded,
            color: accent,
            size: 21,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xffe5f1f0),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
