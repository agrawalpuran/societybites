import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/data.dart';

/// Who receives the delivery fee on cross-society seller delivery orders.
class BuyerDeliveryCollectHint extends StatelessWidget {
  const BuyerDeliveryCollectHint({super.key, required this.order});

  final Order order;

  static const _hintStyle = TextStyle(
    fontSize: 11,
    height: 1.35,
    color: Color(0xFF6A7774),
    fontWeight: FontWeight.w500,
  );

  @override
  Widget build(BuildContext context) {
    if (!order.buyerShowsDeliveryCollectGuidance) {
      return const SizedBox.shrink();
    }

    if (order.deliveryFeeCollectedByPartner) {
      return const Text(
        'Delivery charge to be paid to partner directly',
        style: _hintStyle,
      );
    }

    final upi = order.sellerUpiForOrder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Delivery charge to be paid to seller',
          style: _hintStyle,
        ),
        if (upi != null) ...[
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  upi,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _hintStyle.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF3A4644),
                  ),
                ),
              ),
              InkWell(
                onTap: () => _copyUpi(context, upi),
                borderRadius: BorderRadius.circular(6),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(
                    Icons.copy_rounded,
                    size: 16,
                    color: Color(0xFF0E5A47),
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _copyUpi(BuildContext context, String upi) async {
    await Clipboard.setData(ClipboardData(text: upi));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Seller UPI ID copied'),
        duration: Duration(seconds: 2),
      ),
    );
  }
}

String buyerDeliveryChargeAmountLabel(Order order) {
  if (order.deliveryChargePending) return 'On actuals';
  final charge = order.deliveryCharge;
  if (charge <= 0) return '₹0';
  final label = charge == charge.roundToDouble()
      ? charge.toInt().toString()
      : charge.toStringAsFixed(0);
  return '₹$label';
}
