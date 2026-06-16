import 'package:flutter/material.dart';

import '../widgets/listing_image.dart';
import '../models/data.dart';

class OrderItemsList extends StatelessWidget {
  const OrderItemsList({
    super.key,
    required this.items,
    this.compact = false,
  });

  final List<OrderLineItem> items;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text(
        'No items',
        style: TextStyle(color: Color(0xFF8A9491)),
      );
    }

    return Column(
      children: items.map((item) {
        return Padding(
          padding: EdgeInsets.only(bottom: compact ? 8 : 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListingImage(
                food: item.food,
                width: compact ? 44 : 52,
                height: compact ? 44 : 52,
                borderRadius: compact ? 12 : 14,
                iconSize: compact ? 22 : 26,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.food.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 14 : 15,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF101617),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Qty ${item.quantity} • ${item.food.sellerName}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8A9491),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '₹${item.lineTotal.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: compact ? 14 : 15,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF101617),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class OrderTotalRow extends StatelessWidget {
  const OrderTotalRow({
    super.key,
    required this.order,
  });

  final Order order;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (order.items.length > 1) ...[
          Row(
            children: [
              const Text(
                'Subtotal',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6A7774),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Text(
                '₹${order.subtotal.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3A4644),
                ),
              ),
            ],
          ),
          if (order.communityFee > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Text(
                  'Community fee',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6A7774),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  '₹${order.communityFee.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3A4644),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Text(
              order.paymentMethod == 'cash' ? 'Cash on pickup' : 'UPI',
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF0E5A47),
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Text(
              'Total ₹${order.total.toStringAsFixed(0)}',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF101617),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
