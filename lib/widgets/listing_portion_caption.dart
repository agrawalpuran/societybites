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
