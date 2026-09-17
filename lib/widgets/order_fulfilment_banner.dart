import 'package:flutter/material.dart';

import '../models/data.dart';

class OrderFulfilmentBanner extends StatelessWidget {
  const OrderFulfilmentBanner({
    super.key,
    required this.order,
    required this.isSellerView,
  });

  final Order order;
  final bool isSellerView;

  @override
  Widget build(BuildContext context) {
    final method = order.fulfilmentMethod;
    if (method == null || method.isEmpty) return const SizedBox.shrink();
    final delivery = method == 'seller_delivery';
    final charge = order.deliveryCharge;
    final chargeLabel = charge == charge.roundToDouble()
        ? charge.toInt().toString()
        : charge.toString();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7F4),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD4E8DF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            delivery ? '🛵 SELLER DELIVERY' : '🏠 BUYER PICKUP',
            style: const TextStyle(
              color: Color(0xFF0E5A47),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          if (isSellerView) ...[
            if (order.buyerSocietyName != null &&
                order.buyerSocietyName!.isNotEmpty)
              Text(
                'Buyer Society: ${order.buyerSocietyName}',
                style: const TextStyle(color: Color(0xFF3A4644)),
              ),
            Text(
              delivery
                  ? 'Delivery charge: ₹$chargeLabel'
                  : 'Buyer will collect the order.',
              style: const TextStyle(color: Color(0xFF3A4644)),
            ),
          ] else ...[
            if (order.sellerSocietyName != null &&
                order.sellerSocietyName!.isNotEmpty)
              Text(
                'Seller Society: ${order.sellerSocietyName}',
                style: const TextStyle(color: Color(0xFF3A4644)),
              ),
            Text(
              delivery
                  ? 'Seller will deliver your order.'
                  : 'You will pick up your order from the seller.',
              style: const TextStyle(color: Color(0xFF3A4644)),
            ),
            if (delivery) ...[
              const SizedBox(height: 4),
              Text(
                'Delivery charge: ₹$chargeLabel',
                style: const TextStyle(
                  color: Color(0xFF0E5A47),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
