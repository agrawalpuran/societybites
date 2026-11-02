import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/data.dart';
import '../services/api_service.dart';
import 'order_messages_button.dart';

typedef OrderPhoneRevealer = Future<String> Function(String orderId);
typedef OrderPhoneDialer = Future<bool> Function(String phone);

class OrderCallButton extends StatefulWidget {
  const OrderCallButton({
    super.key,
    required this.order,
    required this.isSellerView,
    this.inline = false,
    this.revealPhone,
    this.dialPhone,
  });

  final Order order;
  final bool isSellerView;
  final bool inline;
  final OrderPhoneRevealer? revealPhone;
  final OrderPhoneDialer? dialPhone;

  @override
  State<OrderCallButton> createState() => _OrderCallButtonState();
}

class _OrderCallButtonState extends State<OrderCallButton> {
  bool _busy = false;
  String? _revealedPhone;

  bool get _allowed => widget.isSellerView
      ? widget.order.sellerMayAccessBuyerPhone
      : widget.order.buyerMayCallSeller;

  String get _peerLabel => widget.isSellerView ? 'buyer' : 'seller';

  Future<String> _defaultReveal(String orderId) async {
    if (widget.isSellerView) {
      final json = await ApiService.revealBuyerContact(orderId: orderId);
      return (json['buyerPhone'] as String?)?.trim() ?? '';
    }
    final json = await ApiService.revealSellerContact(orderId: orderId);
    return (json['sellerPhone'] as String?)?.trim() ?? '';
  }

  Future<bool> _defaultDial(String phone) async {
    if (kIsWeb) return false;
    final uri = Uri(scheme: 'tel', path: phone);
    return launchUrl(uri);
  }

  Future<void> _call() async {
    if (_busy) return;
    final allowed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Call $_peerLabel?'),
        content: const Text(
          'This opens your phone dialer for a normal voice call about this order. Use the number only to complete this order.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF0E5A47)),
            child: const Text('Call'),
          ),
        ],
      ),
    );
    if (allowed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      var phone = (_revealedPhone ?? '').trim();
      if (phone.isEmpty) {
        final reveal = widget.revealPhone ?? _defaultReveal;
        phone = (await reveal(widget.order.id)).trim();
      }
      if (phone.isEmpty) {
        phone = widget.isSellerView
            ? (widget.order.buyerPhone?.trim() ?? '')
            : (widget.order.sellerPhone?.trim() ?? '');
      }
      if (!mounted) return;
      if (phone.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_peerLabel[0].toUpperCase()}${_peerLabel.substring(1)} number is not available',
            ),
          ),
        );
        return;
      }
      _revealedPhone = phone;

      if (kIsWeb) {
        await Clipboard.setData(ClipboardData(text: phone));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Number copied. Paste it in your phone to call.'),
          ),
        );
        return;
      }

      final dial = widget.dialPhone ?? _defaultDial;
      final opened = await dial(phone);
      if (!opened && mounted) {
        await Clipboard.setData(ClipboardData(text: phone));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the phone dialer. Number copied.'),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.userFacingError(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_allowed) return const SizedBox.shrink();

    final boxed = !widget.order.isTerminal;
    const green = Color(0xFF0E5A47);
    final button = OutlinedButton(
      key: const Key('order-call-button'),
      onPressed: _busy ? null : _call,
      style: OutlinedButton.styleFrom(
        foregroundColor: green,
        side: BorderSide(
          color: boxed ? green : const Color(0xFFD4E8DF),
          width: boxed ? 1.6 : 1.2,
        ),
        backgroundColor: boxed ? const Color(0xFFF0F7F4) : Colors.white,
        padding: EdgeInsets.symmetric(
          horizontal: boxed ? 14 : 10,
          vertical: boxed ? 12 : 8,
        ),
        minimumSize: Size(0, boxed ? 40 : 32),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.standard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _busy ? Icons.hourglass_top_rounded : Icons.call_rounded,
            size: 16,
          ),
          const SizedBox(width: 8),
          Text(
            _busy ? 'Calling…' : 'Call',
            maxLines: 1,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: boxed ? 13 : 12,
            ),
          ),
        ],
      ),
    );

    if (widget.inline) return button;
    return Align(alignment: Alignment.centerLeft, child: button);
  }
}

class OrderContactActions extends StatelessWidget {
  const OrderContactActions({
    super.key,
    required this.order,
    required this.isSellerView,
    this.inline = false,
    this.onClosed,
    this.revealPhone,
    this.dialPhone,
  });

  final Order order;
  final bool isSellerView;
  final bool inline;
  final Future<void> Function()? onClosed;
  final OrderPhoneRevealer? revealPhone;
  final OrderPhoneDialer? dialPhone;

  @override
  Widget build(BuildContext context) {
    final row = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        OrderCallButton(
          order: order,
          isSellerView: isSellerView,
          inline: true,
          revealPhone: revealPhone,
          dialPhone: dialPhone,
        ),
        OrderMessagesButton(
          order: order,
          isSellerView: isSellerView,
          inline: true,
          onClosed: onClosed,
        ),
      ],
    );
    if (inline) return row;
    return Align(alignment: Alignment.centerLeft, child: row);
  }
}
