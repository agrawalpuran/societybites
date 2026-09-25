import 'package:flutter/material.dart';

import '../models/data.dart';
import '../screens/order_conversation_screen.dart';

class OrderMessagesButton extends StatefulWidget {
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
  State<OrderMessagesButton> createState() => _OrderMessagesButtonState();
}

class _OrderMessagesButtonState extends State<OrderMessagesButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  int get _unread => widget.order.unreadMessageCount;
  bool get _hasUnread => _unread > 0;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.88,
      upperBound: 1,
    );
    _syncPulse();
  }

  @override
  void didUpdateWidget(OrderMessagesButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.unreadMessageCount != _unread) {
      _syncPulse();
    }
  }

  void _syncPulse() {
    if (_hasUnread) {
      _pulse.repeat(reverse: true);
    } else {
      _pulse.stop();
      _pulse.value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => OrderConversationScreen(
          orderId: widget.order.id,
          orderNumber: widget.order.orderId,
          viewerIsSeller: widget.isSellerView,
        ),
      ),
    );
    if (widget.onClosed != null) await widget.onClosed!();
  }

  @override
  Widget build(BuildContext context) {
    final badgeLabel = _unread > 9 ? '9+' : '$_unread';
    final label = widget.isSellerView ? 'Message Buyer' : 'Message Seller';
    final boxed = !widget.order.isTerminal;
    const accent = Color(0xFFE85D04);
    const green = Color(0xFF0E5A47);

    final button = ScaleTransition(
      scale: _hasUnread ? _pulse : const AlwaysStoppedAnimation(1),
      child: OutlinedButton(
        key: const Key('order-messages-button'),
        onPressed: _open,
        style: OutlinedButton.styleFrom(
          foregroundColor: _hasUnread ? Colors.white : green,
          side: BorderSide(
            color: _hasUnread
                ? accent
                : boxed
                ? green
                : const Color(0xFFD4E8DF),
            width: _hasUnread ? 1.6 : 1,
          ),
          backgroundColor: _hasUnread
              ? accent
              : boxed
              ? const Color(0xFFF0F7F4)
              : Colors.white,
          padding: EdgeInsets.symmetric(
            horizontal: boxed || _hasUnread ? 14 : 10,
            vertical: boxed || _hasUnread ? 10 : 6,
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
            Icon(
              _hasUnread
                  ? Icons.mark_chat_unread_rounded
                  : Icons.chat_bubble_outline_rounded,
              size: 16,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: boxed || _hasUnread ? 13 : 12,
              ),
            ),
            if (_hasUnread) ...[
              const SizedBox(width: 8),
              Container(
                key: const Key('order-unread-dot'),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.all(Radius.circular(999)),
                ),
                child: Text(
                  'New · $badgeLabel',
                  style: const TextStyle(
                    color: accent,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    height: 1.2,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    if (widget.inline) return button;
    return Align(alignment: Alignment.centerLeft, child: button);
  }
}
