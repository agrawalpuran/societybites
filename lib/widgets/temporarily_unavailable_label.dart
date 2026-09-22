import 'package:flutter/material.dart';

class TemporarilyUnavailableLabel extends StatelessWidget {
  const TemporarilyUnavailableLabel({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerRight,
      child: Text(
        compact ? 'Not available now' : 'Temporarily not available',
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        style: TextStyle(
          fontSize: compact ? 10 : 12,
          height: 1.1,
          letterSpacing: 0,
          fontWeight: FontWeight.w800,
          color: const Color(0xFFD94F4F),
        ),
      ),
    );
  }
}
