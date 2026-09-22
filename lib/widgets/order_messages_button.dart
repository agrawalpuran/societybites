import 'package:flutter/material.dart';

import '../models/data.dart';
import '../screens/order_conversation_screen.dart';

class OrderMessagesButton extends StatelessWidget {
  const OrderMessagesButton({
    super.key,
    required this.order,
    required this.isSellerView,
    this.onClosed,
  });

  final Order order;
  final bool isSellerView;
  final Future<void> Function()? onClosed;

  @override
  Widget build(BuildContext context) {
    final label = isSellerView ? 'Message Buyer' : 'Message Seller';
    final hasUnread = order.unreadMessageCount > 0;

    return SizedBox(
      width: double.infinity,
      height: 44,
      child: OutlinedButton(
        key: const Key('order-messages-button'),
        onPressed: () async {
          await Navigator.push<void>(
            context,
            MaterialPageRoute(
              builder: (_) => OrderConversationScreen(
                orderId: order.id,
                orderNumber: order.orderId,
                viewerIsSeller: isSellerView,
              ),
            ),
          );
          if (onClosed != null) await onClosed!();
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF0E5A47),
          side: const BorderSide(color: Color(0xFFD4E8DF)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.chat_bubble_outline_rounded, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
            if (hasUnread) ...[
              const SizedBox(width: 8),
              Container(
                key: const Key('order-unread-dot'),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Color(0xFFE85D04),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
