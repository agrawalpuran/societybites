import 'package:flutter/material.dart';

/// In-place loading copy. Keeps page chrome visible instead of a blank spinner.
class ScreenLoadingNote extends StatelessWidget {
  const ScreenLoadingNote({
    super.key,
    required this.message,
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          message,
          key: const Key('screen-loading-note'),
          style: const TextStyle(
            color: Color(0xFF8A9491),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
