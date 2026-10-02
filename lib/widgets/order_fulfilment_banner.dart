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
    final method = order.fulfilmentMethod?.trim() ?? '';
    final delivery = method == 'seller_delivery';
    // Buyer pickup is the default. Cross-society orders snapshot "pickup";
    // same-society orders often omit the field. Either way the banner is the
    // single place we list where to collect.
    if (isSellerView && method.isEmpty) return const SizedBox.shrink();
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
            if (delivery)
              _placeLine(
                _buyerDeliveryAddress(order),
                order.approxDistanceLabel,
              )
            else if (order.buyerSocietyName != null &&
                order.buyerSocietyName!.isNotEmpty)
              Text(
                'Buyer Society: ${order.buyerSocietyName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF3A4644)),
              ),
            Text(
              delivery
                  ? 'Delivery charge: ₹$chargeLabel'
                  : 'Buyer will collect the order.',
              style: const TextStyle(color: Color(0xFF3A4644)),
            ),
          ] else ...[
            if (!delivery) ...[
              _placeLine(
                _buyerPickupPlace(order),
                order.approxDistanceLabel,
              ),
              if (order.sellerLabel.trim().isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  order.sellerLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF3A4644),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ] else if (order.sellerSocietyName != null &&
                order.sellerSocietyName!.isNotEmpty)
              Text(
                'Seller Society: ${order.sellerSocietyName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF3A4644)),
              ),
            if (delivery)
              const Text(
                'Seller will deliver your order.',
                style: TextStyle(color: Color(0xFF3A4644)),
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

/// Apartment and door on one line. Distance is drawn beside it.
String _buyerPickupPlace(Order order) {
  final parts = <String>[];
  final society = order.sellerSocietyName?.trim() ?? '';
  if (society.isNotEmpty) parts.add(society);
  final door = order.food.locationLabel.trim();
  if (door.isNotEmpty && door != 'Pickup at seller home') parts.add(door);
  return parts.join(' · ');
}

/// Apartment, then flat, on one line. Distance stays visible at the end.
String _buyerDeliveryAddress(Order order) {
  final parts = <String>[];
  final society = order.buyerSocietyName?.trim() ?? '';
  if (society.isNotEmpty) parts.add(society);
  final location = <String>[];
  final block = order.buyerBlock?.trim() ?? '';
  final flat = order.buyerFlatNumber?.trim() ?? '';
  if (block.isNotEmpty) location.add('Block $block');
  if (flat.isNotEmpty) location.add('Flat $flat');
  if (location.isNotEmpty) parts.add(location.join(', '));
  return parts.join(' · ');
}

Widget _placeLine(String place, String distance) {
  if (place.isEmpty && distance.isEmpty) return const SizedBox.shrink();
  const style = TextStyle(
    color: Color(0xFF3A4644),
    fontSize: 13,
    height: 1.2,
  );
  if (distance.isEmpty) {
    return Text(
      place,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
  return Row(
    children: [
      if (place.isNotEmpty)
        Flexible(
          child: Text(
            place,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      Text(
        place.isEmpty ? distance : '  $distance',
        maxLines: 1,
        style: style,
      ),
    ],
  );
}
