import 'package:flutter/material.dart';

import '../models/data.dart';

/// New means listed in the last 48 hours. Rating is shown only when reviews exist.
class ListingRatingMark extends StatelessWidget {
  const ListingRatingMark({
    super.key,
    required this.food,
    this.showNewBadge = true,
  });

  final FoodItem food;

  /// Home list cards show [ListingNewChip] beside the type badge instead.
  final bool showNewBadge;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (showNewBadge && food.isNewListing()) {
      children.add(const ListingNewChip());
    }
    if (food.reviewCount > 0) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 6));
      children.add(_ScoreChip(label: food.rating.toString()));
    } else if (children.isEmpty) {
      children.add(
        const Text(
          '0 review',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF8A9491),
          ),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

/// Small label beside type badges — not a filled CTA like Add.
class ListingNewChip extends StatelessWidget {
  const ListingNewChip({this.dense = false});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 4 : 5,
        vertical: dense ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5EE),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFC5DDD2)),
      ),
      child: Text(
        'NEW',
        style: TextStyle(
          fontSize: dense ? 8 : 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.25,
          color: const Color(0xFF0E5A47),
          height: 1.1,
        ),
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(220),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.star_rounded,
            size: 14,
            color: Colors.amber,
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF3A4644),
            ),
          ),
        ],
      ),
    );
  }
}
