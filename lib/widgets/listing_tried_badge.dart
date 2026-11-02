import 'package:flutter/material.dart';

import '../models/data.dart';

/// Compact overlay for products this buyer completed within 12 months.
class ListingTriedBadge extends StatelessWidget {
  const ListingTriedBadge({
    super.key,
    required this.food,
    this.compact = true,
  });

  final FoodItem food;
  final bool compact;

  static const Color teal = Color(0xFF0F766E);

  @override
  Widget build(BuildContext context) {
    if (!food.purchasedBefore) return const SizedBox.shrink();

    final fontSize = compact ? 8.5 : 10.0;
    final iconSize = compact ? 10.0 : 12.0;
    return Container(
      key: const Key('listing-tried-badge'),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: teal,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.repeat_rounded, size: iconSize, color: Colors.white),
          SizedBox(width: compact ? 3 : 4),
          Text(
            'Tried',
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
