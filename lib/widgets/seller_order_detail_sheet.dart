import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/data.dart';
import 'order_fulfilment_banner.dart';
import 'order_items_list.dart';
import 'order_messages_button.dart';

Future<void> showSellerOrderDetailSheet(
  BuildContext context,
  Order order,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => SellerOrderDetailSheet(order: order),
  );
}

class SellerOrderDetailSheet extends StatelessWidget {
  const SellerOrderDetailSheet({super.key, required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final address = order.buyerAddressForSeller;
    final phone = order.buyerPhone?.trim() ?? '';
    final mapsQuery = order.buyerMapsQuery;
    final bottom = MediaQuery.paddingOf(context).bottom;

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
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF3A4644),
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
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
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
                    label: 'Copy phone',
                    onTap: () => _copy(context, phone, 'Phone number copied'),
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
