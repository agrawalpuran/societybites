import 'package:flutter/material.dart';

import '../models/data.dart';
import '../models/listing_availability.dart';

class MadeToOrderHint extends StatelessWidget {
  const MadeToOrderHint({
    super.key,
    required this.food,
    this.compact = false,
  });

  final FoodItem food;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!food.isMadeToOrder) return const SizedBox.shrink();
    final estimate = formatPreparationEstimate(food.preparationTimeMinutes);
    final short = formatPreparationShort(food.preparationTimeMinutes);
    final unavailable = food.madeToOrderUnavailableToday;
    final label = unavailable
        ? 'Currently unavailable'
        : compact
            ? (short.isEmpty
                ? 'Made to Order'
                : 'Made to Order · $short')
            : (estimate.isEmpty
                ? 'Made to Order · Seller confirms availability'
                : 'Made to Order · $estimate · Seller confirms availability');

    return Padding(
      padding: EdgeInsets.only(top: compact ? 4 : 8),
      child: Text(
        label,
        maxLines: compact ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: compact ? 11 : 12,
          fontWeight: FontWeight.w700,
          color: unavailable
              ? const Color(0xFFD94F4F)
              : const Color(0xFF0E5A47),
        ),
      ),
    );
  }
}
