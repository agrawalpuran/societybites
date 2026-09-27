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
    if (!food.isRecurringReadyNow) return const SizedBox.shrink();
    final primary = food.recurringBuyerLabel.isNotEmpty
        ? food.recurringBuyerLabel
        : (food.recurringUnavailable
            ? 'Temporarily not available'
            : 'Available today');
    final secondary = food.recurringNextLabel;
    final unavailable = food.recurringUnavailable;

    return Padding(
      padding: EdgeInsets.only(top: compact ? 4 : 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            primary,
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
          if (!compact && secondary.isNotEmpty)
            Text(
              secondary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6A7774),
              ),
            ),
        ],
      ),
    );
  }
}
