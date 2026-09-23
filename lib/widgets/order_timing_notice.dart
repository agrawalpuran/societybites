import 'package:flutter/material.dart';

import '../models/data.dart';
import '../models/listing_availability.dart';
import 'preorder_widgets.dart';

/// Checkout / order reminder that this is not a ready-now purchase.
class OrderTimingNotice extends StatelessWidget {
  const OrderTimingNotice({
    super.key,
    required this.foods,
    this.preOrderFulfilmentAt,
  });

  final Iterable<FoodItem> foods;
  final DateTime? preOrderFulfilmentAt;

  @override
  Widget build(BuildContext context) {
    final madeToOrder = foods.where((food) => food.isMadeToOrder).toList();
    final isPreOrder = preOrderFulfilmentAt != null ||
        foods.any((food) => food.isPreOrder || food.isPreOrderCatalog);
    if (madeToOrder.isEmpty && !isPreOrder) return const SizedBox.shrink();

    int? longestPrep;
    for (final food in madeToOrder) {
      final minutes = food.preparationTimeMinutes;
      if (minutes == null || minutes <= 0) continue;
      if (longestPrep == null || minutes > longestPrep) longestPrep = minutes;
    }
    final estimate = formatPreparationEstimate(longestPrep);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFF3D5B5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This is not a regular ready-now order',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 8),
          if (madeToOrder.isNotEmpty) ...[
            const Text(
              'Made to Order',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0E5A47),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              estimate.isEmpty
                  ? 'The seller prepares this after you order and will confirm the timeline.'
                  : '$estimate. The seller confirms availability after you order.',
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: Color(0xFF3A4644),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (madeToOrder.isNotEmpty && isPreOrder) const SizedBox(height: 10),
          if (isPreOrder) ...[
            const Text(
              'Pre-order',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xFFB85C3A),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              preOrderFulfilmentAt != null
                  ? '${formatReadyAt(preOrderFulfilmentAt!)}. This is scheduled fulfilment, not immediate pickup.'
                  : 'This is a scheduled pre-order. The seller will share the fulfilment time.',
              style: const TextStyle(
                fontSize: 13,
                height: 1.35,
                color: Color(0xFF3A4644),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
