import 'package:flutter/material.dart';

import '../models/data.dart';
import 'listing_type_badge.dart';

/// Top of narrow home / nearby carousel cards: type badge + NEW / rating.
class ListingCompactCardHeader extends StatelessWidget {
  const ListingCompactCardHeader({
    super.key,
    required this.food,
    this.isDark = false,
  });

  final FoodItem food;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          Flexible(
            child: Align(
              alignment: Alignment.centerLeft,
              child: ListingTypeBadge(food: food, compact: true),
            ),
          ),
          const SizedBox(width: 6),
          _ListingTrustTrail(food: food, isDark: isDark),
        ],
      ),
    );
  }
}

/// NEW and/or star rating — never "No reviews yet" on compact cards.
class _ListingTrustTrail extends StatelessWidget {
  const _ListingTrustTrail({required this.food, required this.isDark});

  final FoodItem food;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (food.isNewListing()) {
      children.add(const _CompactNewMark());
    }
    if (food.reviewCount > 0) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 4));
      children.add(_CompactRatingMark(rating: food.rating, isDark: isDark));
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}

class _CompactNewMark extends StatelessWidget {
  const _CompactNewMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFF0E5A47),
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Text(
        'NEW',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.35,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}

class _CompactRatingMark extends StatelessWidget {
  const _CompactRatingMark({required this.rating, required this.isDark});

  final double rating;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final fg = isDark ? Colors.white : const Color(0xFF3A4644);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.star_rounded,
          size: 13,
          color: Colors.amber.shade600,
        ),
        const SizedBox(width: 2),
        Text(
          rating.toStringAsFixed(rating == rating.roundToDouble() ? 0 : 1),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: fg,
            height: 1,
          ),
        ),
      ],
    );
  }
}
