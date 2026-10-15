import 'package:flutter/material.dart';

import '../widgets/listing_image.dart';
import '../models/coupon.dart';
import '../models/data.dart';

class OrderItemsList extends StatelessWidget {
  const OrderItemsList({
    super.key,
    required this.items,
    this.compact = false,
    this.showSellerName = true,
    this.order,
    this.showDeliveryBelowLineItems = false,
  });

  final List<OrderLineItem> items;
  final bool compact;
  final bool showSellerName;
  /// When set with [showDeliveryBelowLineItems], delivery shows under item prices.
  final Order? order;
  final bool showDeliveryBelowLineItems;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Text('No items', style: TextStyle(color: Color(0xFF8A9491)));
    }

    return Column(
      children: [
        ...items.map((item) {
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
                        showSellerName
                            ? 'Qty ${item.quantity} • ${item.food.sellerName}'
                            : 'Qty ${item.quantity}',
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
        }),
        ..._deliveryBelowItems(
          order: order,
          enabled: showDeliveryBelowLineItems && !compact,
          itemCount: items.length,
        ),
      ],
    );
  }
}

List<Widget> _deliveryBelowItems({
  required Order? order,
  required bool enabled,
  required int itemCount,
}) {
  if (!enabled || order == null || itemCount != 1) return const [];

  const amountStyle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w800,
    color: Color(0xFF101617),
  );
  const labelStyle = TextStyle(
    fontSize: 11,
    color: Color(0xFF8A9491),
    fontWeight: FontWeight.w600,
  );

  if (order.deliveryChargePending) {
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: const [
                Text('Pending', style: amountStyle),
                SizedBox(height: 2),
                Text('Delivery charge', style: labelStyle),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  if (order.deliveryCharge <= 0) return const [];

  final charge = order.deliveryCharge;
  final chargeText = charge == charge.roundToDouble()
      ? charge.toInt().toString()
      : charge.toStringAsFixed(0);

  return [
    Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('₹$chargeText', style: amountStyle),
              const SizedBox(height: 2),
              const Text('Delivery charge', style: labelStyle),
            ],
          ),
        ],
      ),
    ),
  ];
}

class OrderTotalRow extends StatelessWidget {
  const OrderTotalRow({super.key, required this.order});

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
                  'Platform fee',
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
          if ((order.couponDiscount ?? 0) > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                Text(
                  'Coupon${order.couponCode == null ? '' : ' (${order.couponCode})'}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6A7774),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  '-${formatRupee(order.couponDiscount!)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0E5A47),
                  ),
                ),
              ],
            ),
          ],
          if (order.deliveryChargePending) ...[
            const SizedBox(height: 4),
            const Row(
              children: [
                Expanded(
                  child: Text(
                    'Delivery charge (confirmed when ready)',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6A7774),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Text(
                  'Pending',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6A7774),
                  ),
                ),
              ],
            ),
          ] else if (order.deliveryCharge > 0) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                const Text(
                  'Seller delivery',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6A7774),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  '₹${order.deliveryCharge.toStringAsFixed(0)}',
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
