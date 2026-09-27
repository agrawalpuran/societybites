import 'package:flutter/material.dart';

import '../models/data.dart';

class RecurringAvailabilityHint extends StatelessWidget {
  const RecurringAvailabilityHint({
    super.key,
    required this.food,
    this.compact = false,
  });

  final FoodItem food;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (!food.showsBuyerAvailabilityHint) return const SizedBox.shrink();
    final unavailable = food.recurringUnavailable;
    final window = food.recurringWindowLabel;
    final primary = unavailable
        ? 'Not available now'
        : (food.recurringBuyerLabel.isNotEmpty
            ? food.recurringBuyerLabel
            : 'Available today');
    final extra = <String>[];
    if (unavailable) {
      if (window.isNotEmpty) extra.add(window);
      if (!compact && food.recurringNextLabel.isNotEmpty) {
        extra.add(food.recurringNextLabel);
      } else if (window.isEmpty && food.recurringNextLabel.isNotEmpty) {
        extra.add(food.recurringNextLabel);
      }
    } else if (!compact) {
      if (window.isNotEmpty && !primary.contains(window)) extra.add(window);
      if (food.recurringNextLabel.isNotEmpty) extra.add(food.recurringNextLabel);
    }

    return Padding(
      padding: EdgeInsets.only(top: compact ? 4 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            primary,
            maxLines: compact ? 2 : 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
              height: 1.2,
              color: unavailable
                  ? const Color(0xFFD94F4F)
                  : const Color(0xFF0E5A47),
            ),
          ),
          for (final line in extra)
            Text(
              line,
              maxLines: compact ? 2 : 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 11 : 12,
                fontWeight: FontWeight.w600,
                height: 1.25,
                color: const Color(0xFF6A7774),
              ),
            ),
        ],
      ),
    );
  }
}
