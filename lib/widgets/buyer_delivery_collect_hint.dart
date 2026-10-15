import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/data.dart';

/// Who receives the delivery fee on cross-society seller delivery orders.
class BuyerDeliveryCollectHint extends StatelessWidget {
  const BuyerDeliveryCollectHint({super.key, required this.order});

  final Order order;

  static const _noteStyle = TextStyle(
    fontSize: 11,
    height: 1.35,
    color: Color(0xFF101617),
    fontWeight: FontWeight.w700,
  );

  @override
  Widget build(BuildContext context) {
    if (!order.buyerShowsDeliveryCollectGuidance) {
      return const SizedBox.shrink();
    }

    if (order.deliveryFeeCollectedByPartner) {
      return const Text(
        'Please note: Delivery charge to be paid to delivery partner directly',
        style: _noteStyle,
      );
    }

    final upi = order.sellerUpiForOrder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Please note: Delivery charge to be paid to seller',
          style: _noteStyle,
        ),
        if (upi != null) ...[
          const SizedBox(height: 4),
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 2,
            children: [
              Text(
                upi,
                style: _noteStyle,
              ),
              InkWell(
                onTap: () => _copyUpi(context, upi),
                borderRadius: BorderRadius.circular(4),
                child: const Padding(
                  padding: EdgeInsets.all(2),
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
