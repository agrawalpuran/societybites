import 'package:flutter/material.dart';

import '../models/data.dart';
import '../screens/order_conversation_screen.dart';

class OrderMessagesButton extends StatelessWidget {
  const OrderMessagesButton({
    super.key,
    required this.order,
    required this.isSellerView,
    this.onClosed,
    this.inline = false,
  });

  final Order order;
  final bool isSellerView;
  final Future<void> Function()? onClosed;
  final bool inline;

  @override
  Widget build(BuildContext context) {
    final unread = order.unreadMessageCount;
    final badgeLabel = unread > 9 ? '9+' : '$unread';
    final label = isSellerView ? 'Message Buyer' : 'Message Seller';
    final boxed = !order.isTerminal;

    final button = OutlinedButton(
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
          side: BorderSide(
            color: boxed ? const Color(0xFF0E5A47) : const Color(0xFFD4E8DF),
          ),
          backgroundColor: boxed ? const Color(0xFFF0F7F4) : Colors.white,
          padding: EdgeInsets.symmetric(
            horizontal: boxed ? 14 : 10,
            vertical: boxed ? 10 : 6,
          ),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.chat_bubble_outline_rounded, size: 16),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: boxed ? 13 : 12,
              ),
            ),
            if (unread > 0) ...[
              const SizedBox(width: 8),
              Container(
                key: const Key('order-unread-dot'),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: const BoxDecoration(
                  color: Color(0xFFE85D04),
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
                child: Text(
                  badgeLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ],
        ),
    );

    if (inline) return button;
    return Align(alignment: Alignment.centerLeft, child: button);
  }
}
