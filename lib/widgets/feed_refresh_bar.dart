import 'package:flutter/material.dart';

/// Thin progress for stale-while-revalidate / background home refresh.
class FeedRefreshBar extends StatelessWidget {
  const FeedRefreshBar({super.key, this.visible = false});

  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return const LinearProgressIndicator(
      minHeight: 2,
      backgroundColor: Color(0xFFE6EBE9),
      color: Color(0xFF0E5A47),
    );
  }
}
