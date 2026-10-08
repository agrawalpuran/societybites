import 'package:flutter/material.dart';

import '../models/data.dart';
import '../utils/listing_portion_label.dart';

/// Compact portion size under price on home / web cards.
class ListingPortionCaption extends StatelessWidget {
  const ListingPortionCaption({
    super.key,
    required this.food,
    this.style,
    this.isDark = false,
  });

  final FoodItem food;
  final TextStyle? style;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final label = portionLabelForFood(food);
    if (label == null) return const SizedBox.shrink();

    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style ??
          TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white70 : const Color(0xFF6A7774),
          ),
    );
  }
}

/// Price with pack size on its own line so Add never clips the unit (carousel cards).
class ListingCompactPriceRow extends StatelessWidget {
  const ListingCompactPriceRow({
    super.key,
    required this.food,
    this.isDark = false,
  });

  final FoodItem food;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final portion = portionLabelForFood(food);
    final priceStyle = TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w800,
      color: isDark ? Colors.white : const Color(0xFF101617),
      height: 1.05,
    );
    final unitStyle = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w600,
      color: isDark ? Colors.white70 : const Color(0xFF6A7774),
      height: 1.15,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('₹${food.price.toStringAsFixed(0)}', style: priceStyle),
        if (portion != null)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              portion,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: unitStyle,
            ),
          ),
      ],
    );
  }
}
