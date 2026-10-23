import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/data.dart';
import '../services/api_service.dart';
import 'order_fulfilment_banner.dart';
import 'order_items_list.dart';
import 'order_messages_button.dart';

typedef BuyerPhoneRevealer = Future<String> Function(String orderId);

Future<void> showSellerOrderDetailSheet(
  BuildContext context,
  Order order, {
  BuyerPhoneRevealer? revealBuyerPhone,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SellerOrderDetailSheet(
      order: order,
      revealBuyerPhone: revealBuyerPhone,
    ),
  );
}

class SellerOrderDetailSheet extends StatefulWidget {
  const SellerOrderDetailSheet({
    super.key,
    required this.order,
    this.revealBuyerPhone,
  });

  final Order order;
  final BuyerPhoneRevealer? revealBuyerPhone;

  @override
  State<SellerOrderDetailSheet> createState() => _SellerOrderDetailSheetState();
}

class _SellerOrderDetailSheetState extends State<SellerOrderDetailSheet> {
  String? _revealedPhone;
  bool _revealing = false;

  Order get order => widget.order;

  Future<void> _showNumber() async {
    final allowed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Show buyer number?'),
        content: const Text(
          'Use this number only to complete this order. Do not save it or use it for anything else.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: const Color(0xFF0E5A47)),
            child: const Text('Show number'),
          ),
        ],
      ),
    );
    if (allowed != true || !mounted) return;

    setState(() => _revealing = true);
    try {
      final reveal = widget.revealBuyerPhone ??
          ((id) async {
            final json = await ApiService.revealBuyerContact(orderId: id);
            return (json['buyerPhone'] as String?)?.trim() ?? '';
          });
      final phone = (await reveal(order.id)).trim();
      if (!mounted) return;
      if (phone.isEmpty) {
        final fallback = order.buyerPhone?.trim() ?? '';
        if (fallback.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Buyer number is not available')),
          );
          return;
        }
        setState(() => _revealedPhone = fallback);
        return;
      }
      setState(() => _revealedPhone = phone);
    } catch (e) {
      if (!mounted) return;
      final fallback = order.sellerMayAccessBuyerPhone
          ? (order.buyerPhone?.trim() ?? '')
          : '';
      if (fallback.isNotEmpty) {
        setState(() => _revealedPhone = fallback);
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.userFacingError(e))),
      );
    } finally {
      if (mounted) setState(() => _revealing = false);
    }
  }

  String? _lockedHint() {
    if (order.isSellerDelivery && !order.sellerMayAccessBuyerPhone) {
      if (order.status == 'pending') {
        return 'Buyer number is shown after you accept this order.';
      }
      return 'Buyer number is shown after payment is confirmed.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final address = order.buyerAddressForSeller;
    final phone = _revealedPhone?.trim() ?? '';
    final mapsQuery = order.buyerMapsQuery;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final mayAccess = order.sellerMayAccessBuyerPhone;
    final masked = order.buyerPhoneMasked?.trim() ?? '';
    final lockedHint = _lockedHint();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.78,
      minChildSize: 0.45,
      maxChildSize: 0.94,
      builder: (_, controller) {
        return ListView(
          key: const Key('seller-order-detail-sheet'),
          controller: controller,
          padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottom),
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD4E8DF),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              order.orderId,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF101617),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              order.placedAtLabel,
              style: const TextStyle(
                color: Color(0xFF6A7774),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'BUYER',
              style: TextStyle(
                fontSize: 11,
                letterSpacing: 0.7,
                fontWeight: FontWeight.w800,
                color: Color(0xFF6A7774),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              order.buyerNameLabel,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF101617),
              ),
            ),
            if (phone.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                phone,
                key: const Key('seller-order-buyer-phone'),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3A4644),
                ),
              ),
            ] else if (mayAccess && masked.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                masked,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6A7774),
                ),
              ),
            ],
            if (address.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                address,
                style: const TextStyle(
                  fontSize: 15,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3A4644),
                ),
              ),
            ],
            if (order.approxDistanceLabel.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                order.approxDistanceLabel,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0E5A47),
                ),
              ),
            ],
            if (lockedHint != null) ...[
              const SizedBox(height: 10),
              Text(
                lockedHint,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6A7774),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (mayAccess && phone.isEmpty)
                  _ActionChip(
                    key: const Key('seller-order-show-buyer-phone'),
                    icon: Icons.phone_outlined,
                    label: _revealing ? 'Showing…' : 'Show number',
                    onTap: _revealing ? () {} : _showNumber,
                  ),
                if (phone.isNotEmpty)
                  _ActionChip(
                    key: const Key('seller-order-call-buyer'),
                    icon: Icons.call_rounded,
                    label: 'Call',
                    onTap: () => _callBuyer(context, phone),
                  ),
                if (phone.isNotEmpty)
                  _ActionChip(
                    icon: Icons.copy_rounded,
                    label: 'Copy',
                    onTap: () => _copy(context, phone, 'Number copied'),
                  ),
                if (mapsQuery.isNotEmpty)
                  _ActionChip(
                    key: const Key('seller-order-open-maps'),
                    icon: Icons.map_outlined,
                    label: 'Open maps',
                    onTap: () => _openMaps(context, mapsQuery),
                  ),
              ],
            ),
            if (order.fulfilmentMethod != null &&
                order.fulfilmentMethod!.isNotEmpty) ...[
              const SizedBox(height: 16),
              OrderFulfilmentBanner(order: order, isSellerView: true),
            ],
            const Divider(height: 28),
            OrderItemsList(
              items: order.items,
              showSellerName: false,
              order: order,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Total',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF101617),
                    ),
                  ),
                ),
                Text(
                  '₹${order.total.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0E5A47),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: OrderMessagesButton(
                order: order,
                isSellerView: true,
              ),
            ),
          ],
        );
      },
    );
  }

  static Future<void> _callBuyer(BuildContext context, String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (!await launchUrl(uri)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the phone dialer')),
      );
    }
  }

  static Future<void> _openMaps(BuildContext context, String query) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(query)}',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open maps')),
      );
    }
  }

  static Future<void> _copy(
    BuildContext context,
    String value,
    String message,
  ) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

class _ActionChip extends StatelessWidget {
  const _ActionChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF0E5A47),
        side: const BorderSide(color: Color(0xFFD4E8DF)),
        backgroundColor: const Color(0xFFF0F7F4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon, size: 18),
      label: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );
  }
}
