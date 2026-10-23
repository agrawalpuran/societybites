import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../web/web_page_frame.dart';
import '../../widgets/admin_loading_panel.dart';

class AdminOrderDetailScreen extends StatefulWidget {
  const AdminOrderDetailScreen({
    super.key,
    required this.orderId,
    this.loadOrder,
  });

  final String orderId;

  /// Test seam. Production uses [ApiService.getAdminOrder].
  final Future<Map<String, dynamic>> Function(String orderId)? loadOrder;

  @override
  State<AdminOrderDetailScreen> createState() => _AdminOrderDetailScreenState();
}

class _AdminOrderDetailScreenState extends State<AdminOrderDetailScreen> {
  Map<String, dynamic>? _order;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final load = widget.loadOrder ?? ApiService.getAdminOrder;
      final order = await load(widget.orderId);
      if (!mounted) return;
      setState(() {
        _order = order;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ApiService.userFacingError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final number = order?['orderNumber']?.toString() ?? 'Order';
    return panelOnWeb(
      context,
      Scaffold(
        backgroundColor: const Color(0xFFF8FAF9),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0E5A47),
          foregroundColor: Colors.white,
          title: Text(
            number == 'Order' ? number : '#$number',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const AdminLoadingPanel(message: 'Loading order…');
    }
    if (_error != null || _order == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error ?? 'Order not found',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF6A7774)),
              ),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final order = _order!;
    final buyer = _asMap(order['buyer']);
    final sellers = _asMapList(order['sellers']);
    final items = _asMapList(order['items']);
    final coupon = _asMap(order['coupon']);
    final timeline = _asMap(order['timeline']);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      children: [
        _Section(
          title: 'Order',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StatusBadge(
                    status: order['status']?.toString() ?? 'pending',
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _orderTypeLabel(order['type']?.toString()),
                    style: const TextStyle(
                      color: Color(0xFF6A7774),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Field(
                'Fulfilment',
                _fulfilmentLabel(order['fulfilmentMethod']?.toString()),
              ),
              _Field('Placed', _formatDate(order['createdAt']?.toString())),
              _Field('Updated', _formatDate(order['updatedAt']?.toString())),
              if (_present(order['fulfilmentAt']))
                _Field(
                  'Fulfilment time',
                  _formatDate(order['fulfilmentAt']?.toString()),
                ),
              if (_present(order['expectedReadyAt']))
                _Field(
                  'Expected ready',
                  _formatDate(order['expectedReadyAt']?.toString()),
                ),
              if (_present(order['requestedReadyAt']))
                _Field(
                  'Requested ready',
                  _formatDate(order['requestedReadyAt']?.toString()),
                ),
              _societyFields('Order society', _asMap(order['society'])),
            ],
          ),
        ),
        _Section(
          title: 'Items',
          child: items.isEmpty
              ? const Text(
                  'No items',
                  style: TextStyle(color: Color(0xFF6A7774)),
                )
              : Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0) const Divider(height: 20),
                      _ItemRow(item: items[i]),
                    ],
                  ],
                ),
        ),
        _Section(
          title: 'Payment',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Field('Method', _label(order['paymentMethod']?.toString())),
              _Field('Status', _label(order['paymentStatus']?.toString())),
              _Field('Subtotal', _money(order['subtotal'])),
              _Field('Delivery', _money(order['deliveryCharge'])),
              _Field('Platform fee', _money(order['communityFee'])),
              if (coupon != null) ...[
                _Field('Coupon', coupon['code']?.toString() ?? '—'),
                _Field('Discount', _money(coupon['discountAmount'])),
              ],
              _Field('Total', _money(order['total']), emphasize: true),
              if (_present(order['upiTransactionRef']))
                _Field('UPI reference', order['upiTransactionRef'].toString()),
              if (_present(order['buyerMarkedPaidAt']))
                _Field(
                  'Buyer marked paid',
                  _formatDate(order['buyerMarkedPaidAt'].toString()),
                ),
              if (_present(order['sellerConfirmedPaidAt']))
                _Field(
                  'Seller confirmed',
                  _formatDate(order['sellerConfirmedPaidAt'].toString()),
                ),
              if (_present(order['deliveryCollectBy']))
                _Field(
                  'Delivery cash',
                  _collectByLabel(order['deliveryCollectBy'].toString()),
                ),
              if (_present(order['deliveryCashConfirmedAt']))
                _Field(
                  'Delivery cash received',
                  _formatDate(order['deliveryCashConfirmedAt'].toString()),
                ),
            ],
          ),
        ),
        _PartySection(title: 'Buyer', party: buyer),
        if (sellers.isEmpty)
          const _Section(
            title: 'Seller',
            child: Text(
              'No seller on this order',
              style: TextStyle(color: Color(0xFF6A7774)),
            ),
          )
        else
          for (final seller in sellers)
            _PartySection(title: 'Seller', party: seller, seller: true),
        if (_hasNotes(order))
          _Section(
            title: 'Notes',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_present(order['fulfilmentNotes']))
                  _Field('Fulfilment', order['fulfilmentNotes'].toString()),
                if (_present(order['cancelReason']))
                  _Field('Cancellation', order['cancelReason'].toString()),
                if (_present(order['rejectReason']))
                  _Field('Rejection', order['rejectReason'].toString()),
              ],
            ),
          ),
        _Section(
          title: 'Timeline',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Field(
                'Placed',
                _formatDate(
                  timeline?['createdAt']?.toString() ??
                      order['createdAt']?.toString(),
                ),
              ),
              if (_present(timeline?['acceptedAt']))
                _Field(
                  'Accepted',
                  _formatDate(timeline!['acceptedAt'].toString()),
                ),
              if (_present(timeline?['preparingAt']))
                _Field(
                  'Preparing',
                  _formatDate(timeline!['preparingAt'].toString()),
                ),
              if (_present(timeline?['readyAt']))
                _Field('Ready', _formatDate(timeline!['readyAt'].toString())),
              if (_present(timeline?['pickedUpAt']))
                _Field(
                  'Picked up',
                  _formatDate(timeline!['pickedUpAt'].toString()),
                ),
              if (_present(timeline?['completedAt']))
                _Field(
                  'Completed',
                  _formatDate(timeline!['completedAt'].toString()),
                ),
              if (_present(timeline?['cancelledAt']))
                _Field(
                  'Cancelled',
                  _formatDate(timeline!['cancelledAt'].toString()),
                ),
              if (_present(order['rejectedAt']))
                _Field('Rejected', _formatDate(order['rejectedAt'].toString())),
            ],
          ),
        ),
      ],
    );
  }
}

class _PartySection extends StatelessWidget {
  const _PartySection({
    required this.title,
    required this.party,
    this.seller = false,
  });

  final String title;
  final Map<String, dynamic>? party;
  final bool seller;

  @override
  Widget build(BuildContext context) {
    if (party == null) {
      return _Section(
        title: title,
        child: const Text(
          'Not available',
          style: TextStyle(color: Color(0xFF6A7774)),
        ),
      );
    }
    final flatHidden = party!['hideFlatNumber'] == true;
    return _Section(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Field('Name', _text(party!['name'])),
          _Field('Phone', _text(party!['phone'])),
          _Field('Role', _label(party!['role']?.toString())),
          _flatFields(party!['flat']),
          _societyFields('Society', _asMap(party!['society'])),
          if (seller) ...[
            _Field('UPI ID', _text(party!['upiId'])),
            _Field('UPI name', _text(party!['upiDisplayName'])),
            _Field(
              'Fulfilment mode',
              _fulfilmentModeLabel(party!['fulfilmentMode']?.toString()),
            ),
            if (flatHidden)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text(
                  'This flat is hidden from buyers in the app. It is shown here for support.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8A5A00),
                    height: 1.35,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final listing = _asMap(item['listing']);
    final name = listing?['name']?.toString() ?? 'Item';
    final seller = listing?['sellerName']?.toString();
    final pickup = listing?['pickupLocation']?.toString();
    final qty = item['quantity'] ?? 0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101617),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                [
                  'Qty $qty × ${_money(item['unitPrice'])}',
                  if (seller != null && seller.isNotEmpty) seller,
                  if (pickup != null && pickup.isNotEmpty) pickup,
                ].join(' · '),
                style: const TextStyle(fontSize: 12, color: Color(0xFF6A7774)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          _money(item['lineTotal']),
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF0E5A47),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
                color: Color(0xFF0E5A47),
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value, {this.emphasize = false});

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 128,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF8A9491)),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: emphasize ? 15 : 13,
                fontWeight: emphasize ? FontWeight.w800 : FontWeight.w600,
                color: emphasize
                    ? const Color(0xFF0E5A47)
                    : const Color(0xFF101617),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  Color get _color {
    switch (status) {
      case 'completed':
        return const Color(0xFF2E7D32);
      case 'cancelled':
      case 'rejected':
        return const Color(0xFFC62828);
      case 'pending':
        return const Color(0xFFF57C00);
      case 'accepted':
      case 'confirmed':
      case 'preparing':
      case 'ready':
        return const Color(0xFF1565C0);
      default:
        return const Color(0xFF6A7774);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        _label(status),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _color,
        ),
      ),
    );
  }
}

Widget _flatFields(dynamic flat) {
  final map = _asMap(flat);
  if (map == null) return const _Field('Flat', '—');
  final parts = <String>[
    if (_present(map['block'])) 'Block ${map['block']}',
    if (_present(map['flatNumber'])) 'Flat ${map['flatNumber']}',
    if (map['floor'] != null) 'Floor ${map['floor']}',
    if (_present(map['unit'])) 'Unit ${map['unit']}',
  ];
  return _Field('Flat', parts.isEmpty ? '—' : parts.join(', '));
}

Widget _societyFields(String label, Map<String, dynamic>? society) {
  if (society == null) return _Field(label, '—');
  final place = [
    society['city']?.toString().trim(),
    society['state']?.toString().trim(),
    society['pincode']?.toString().trim(),
  ].where((part) => part != null && part.isNotEmpty).join(', ');
  final lines = [
    if (_present(society['name'])) society['name'].toString(),
    if (_present(society['address'])) society['address'].toString(),
    if (place.isNotEmpty) place,
  ];
  return _Field(label, lines.isEmpty ? '—' : lines.join('\n'));
}

bool _hasNotes(Map<String, dynamic> order) {
  return _present(order['fulfilmentNotes']) ||
      _present(order['cancelReason']) ||
      _present(order['rejectReason']);
}

bool _present(dynamic value) {
  if (value == null) return false;
  return value.toString().trim().isNotEmpty;
}

String _text(dynamic value) {
  if (!_present(value)) return '—';
  return value.toString();
}

String _label(String? raw) {
  if (raw == null || raw.trim().isEmpty) return '—';
  final words = raw.trim().replaceAll('_', ' ').split(RegExp(r'\s+'));
  return words
      .map(
        (word) => word.isEmpty
            ? word
            : '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}',
      )
      .join(' ');
}

String _orderTypeLabel(String? type) {
  if (type == 'pre_order') return 'Pre-order';
  return 'Regular';
}

String _fulfilmentLabel(String? method) {
  switch (method) {
    case 'seller_delivery':
      return 'Seller delivery';
    case 'pickup':
    case 'buyer_pickup':
      return 'Buyer pickup';
    case null:
    case '':
      return 'Buyer pickup';
    default:
      return _label(method);
  }
}

String _fulfilmentModeLabel(String? mode) {
  switch (mode) {
    case 'BUYER_PICKUP':
      return 'Buyer pickup';
    case 'SELLER_DELIVERY':
      return 'Seller delivery';
    case 'BOTH':
      return 'Pickup and delivery';
    default:
      return _label(mode);
  }
}

String _collectByLabel(String value) {
  switch (value) {
    case 'seller':
      return 'Seller collects';
    case 'delivery_person':
      return 'Delivery person collects';
    default:
      return _label(value);
  }
}

String _money(dynamic value) {
  final number = value is num
      ? value.toDouble()
      : double.tryParse('${value ?? ''}') ?? 0;
  if (number == number.roundToDouble()) return '₹${number.toInt()}';
  return '₹${number.toStringAsFixed(2)}';
}

String _formatDate(String? iso) {
  if (iso == null || iso.isEmpty) return '—';
  try {
    final date = DateTime.parse(iso).toLocal();
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$day/$month/${date.year} $hour:$minute';
  } catch (_) {
    return iso;
  }
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

List<Map<String, dynamic>> _asMapList(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList();
}
