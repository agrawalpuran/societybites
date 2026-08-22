import 'package:flutter/material.dart';

import '../models/data.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../widgets/preorder_widgets.dart';

enum PreOrderPaymentMethod { upi, cash }

class PreOrderCheckoutScreen extends StatefulWidget {
  const PreOrderCheckoutScreen({
    super.key,
    required this.campaign,
    required this.selectedItems,
  });

  final PreOrderCampaign campaign;
  final Map<PreOrderProduct, int> selectedItems;

  @override
  State<PreOrderCheckoutScreen> createState() => _PreOrderCheckoutScreenState();
}

class _PreOrderCheckoutScreenState extends State<PreOrderCheckoutScreen> {
  late String _fulfilmentMethod;
  PreOrderPaymentMethod _payment = PreOrderPaymentMethod.upi;
  double _platformFee = 0;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _fulfilmentMethod =
        widget.campaign.offeredFulfilmentMethods.contains('pickup')
        ? 'pickup'
        : 'seller_delivery';
    _loadPlatformFee();
  }

  Future<void> _loadPlatformFee() async {
    try {
      final fee = await ApiService.getPlatformFee();
      if (mounted) setState(() => _platformFee = fee);
    } catch (_) {}
  }

  double get _subtotal => widget.selectedItems.entries.fold<double>(
    0,
    (sum, entry) => sum + entry.key.price * entry.value,
  );

  double get _estimatedDeliveryCharge => _fulfilmentMethod == 'seller_delivery'
      ? widget.campaign.defaultDeliveryCharge
      : 0;

  double get _estimatedTotal =>
      _subtotal + _platformFee + _estimatedDeliveryCharge;

  Future<void> _placeOrder() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    try {
      final societyId =
          await SessionService.getSocietyId() ??
          SessionService.defaultSocietyId;
      final raw = await ApiService.createOrder(
        societyId: societyId,
        type: 'pre_order',
        campaignId: widget.campaign.id,
        fulfilmentMethod: _fulfilmentMethod,
        paymentMethod: _payment == PreOrderPaymentMethod.upi ? 'upi' : 'cash',
        items: widget.selectedItems.entries
            .map(
              (entry) => {
                'listingId': entry.key.listingId,
                'quantity': entry.value,
              },
            )
            .toList(),
      );
      final order = Order.fromJson(raw);
      if (!mounted) return;
      final confirmed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => PreOrderConfirmationScreen(
            campaign: widget.campaign,
            order: order,
          ),
        ),
      );
      if (confirmed == true && mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_buyerOrderError(e)),
          backgroundColor: const Color(0xFFD94F4F),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  String _buyerOrderError(Object error) {
    final message = cleanApiError(error);
    final lower = error.toString().toLowerCase();
    if (lower.contains('cutoff') ||
        lower.contains('closed') ||
        lower.contains('not open')) {
      return 'Pre-orders for this campaign have closed.';
    }
    if (lower.contains('available') ||
        lower.contains('sold out') ||
        lower.contains('quantity')) {
      return 'One of your selected quantities is no longer available. Go back and refresh the campaign.';
    }
    if (lower.contains('mix') || lower.contains('same campaign')) {
      return 'Pre-orders must be placed separately from regular orders or orders from another seller.';
    }
    return message;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: preorderBackground,
      appBar: AppBar(
        backgroundColor: preorderBackground,
        foregroundColor: preorderText,
        elevation: 0,
        title: const Text(
          'Review pre-order',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _section('SELLER'),
                _card(
                  child: Text(
                    widget.campaign.sellerName,
                    style: const TextStyle(
                      color: preorderText,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _section('ITEMS'),
                _card(
                  child: Column(
                    children: widget.selectedItems.entries.map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${entry.key.name} × ${entry.value}',
                                style: const TextStyle(
                                  color: preorderText,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            Text(
                              formatMoney(entry.key.price * entry.value),
                              style: const TextStyle(
                                color: preorderText,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 20),
                _section('HOW WOULD YOU LIKE TO RECEIVE YOUR ORDER?'),
                if (widget.campaign.offeredFulfilmentMethods.contains('pickup'))
                  _option(
                    value: 'pickup',
                    icon: Icons.shopping_bag_outlined,
                    title: 'Pickup',
                    subtitle: 'Pickup from seller · Delivery charge ₹0',
                  ),
                if (widget.campaign.offeredFulfilmentMethods.contains(
                  'seller_delivery',
                )) ...[
                  const SizedBox(height: 10),
                  _option(
                    value: 'seller_delivery',
                    icon: Icons.delivery_dining_outlined,
                    title: 'Seller delivery',
                    subtitle:
                        '${formatMoney(widget.campaign.defaultDeliveryCharge)} once per seller order',
                  ),
                ],
                const SizedBox(height: 12),
                if (_fulfilmentMethod == 'seller_delivery')
                  _deliveryDisclaimer()
                else
                  const Text(
                    'Pickup from seller.',
                    style: TextStyle(
                      color: preorderGreen,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                const SizedBox(height: 22),
                _section('PAYMENT METHOD'),
                _paymentOption(
                  PreOrderPaymentMethod.upi,
                  Icons.account_balance_wallet_rounded,
                  'UPI payment',
                  "Direct transfer to the seller's UPI",
                ),
                const SizedBox(height: 10),
                _paymentOption(
                  PreOrderPaymentMethod.cash,
                  Icons.money_rounded,
                  'Cash',
                  _fulfilmentMethod == 'pickup'
                      ? 'Pay when you collect your order'
                      : 'Settle directly with the seller',
                ),
                const SizedBox(height: 22),
                _section('ORDER TOTAL'),
                _bill(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _bill() => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        colors: [Color(0xFFFFF5EE), Color(0xFFFEECE0)],
      ),
      borderRadius: BorderRadius.circular(22),
    ),
    child: Column(
      children: [
        _billRow('Food subtotal', _subtotal),
        if (_platformFee > 0) _billRow('Platform fee', _platformFee),
        _billRow(
          _fulfilmentMethod == 'seller_delivery' ? 'Seller delivery' : 'Pickup',
          _estimatedDeliveryCharge,
        ),
        const Divider(height: 28),
        _billRow('Estimated total', _estimatedTotal, emphasized: true),
        const SizedBox(height: 6),
        const Text(
          'The backend confirms the final delivery charge and total when the order is placed.',
          style: TextStyle(
            color: Color(0xFF7A5A42),
            fontSize: 11,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 18),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: _submitting ? null : _placeOrder,
            style: ElevatedButton.styleFrom(
              backgroundColor: preorderGreen,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Place pre-order',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
          ),
        ),
      ],
    ),
  );

  Widget _billRow(String label, double value, {bool emphasized = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 9),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: const Color(0xFF5A4A3A),
                  fontSize: emphasized ? 17 : 14,
                  fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
            Text(
              formatMoney(value),
              style: TextStyle(
                color: const Color(0xFF2A1A0A),
                fontSize: emphasized ? 24 : 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );

  Widget _option({
    required String value,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final selected = _fulfilmentMethod == value;
    return _selectable(
      selected: selected,
      onTap: () => setState(() => _fulfilmentMethod = value),
      icon: icon,
      title: title,
      subtitle: subtitle,
    );
  }

  Widget _paymentOption(
    PreOrderPaymentMethod value,
    IconData icon,
    String title,
    String subtitle,
  ) {
    final selected = _payment == value;
    return _selectable(
      selected: selected,
      onTap: () => setState(() => _payment = value),
      icon: icon,
      title: title,
      subtitle: subtitle,
    );
  }

  Widget _selectable({
    required bool selected,
    required VoidCallback onTap,
    required IconData icon,
    required String title,
    required String subtitle,
  }) => Material(
    color: selected ? const Color(0xFFF0F7F4) : Colors.white,
    borderRadius: BorderRadius.circular(17),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(17),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: selected ? preorderGreen : preorderBorder,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? preorderGreen : preorderMuted),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: preorderText,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: preorderMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: selected ? preorderGreen : const Color(0xFFADB5B2),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _deliveryDisclaimer() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF5EE),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: const Color(0xFFFFE0CC)),
    ),
    child: const Text(
      'SocietyBites does not currently provide delivery services. Delivery '
      'is arranged directly with the seller. Any delivery charge is paid/'
      'settled with the seller.',
      style: TextStyle(
        color: Color(0xFF7A5A42),
        height: 1.4,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _section(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Text(
      text,
      style: const TextStyle(
        color: preorderMuted,
        fontSize: 11,
        letterSpacing: 1.1,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _card({required Widget child}) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: preorderBorder),
    ),
    child: child,
  );
}

class PreOrderConfirmationScreen extends StatelessWidget {
  const PreOrderConfirmationScreen({
    super.key,
    required this.campaign,
    required this.order,
  });

  final PreOrderCampaign campaign;
  final Order order;

  @override
  Widget build(BuildContext context) {
    final sellerDelivery = order.fulfilmentMethod == 'seller_delivery';
    return Scaffold(
      backgroundColor: preorderBackground,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 650),
              child: Column(
                children: [
                  const SizedBox(height: 24),
                  Container(
                    width: 72,
                    height: 72,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE8F5EE),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: preorderGreen,
                      size: 42,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Pre-order confirmed',
                    style: TextStyle(
                      color: preorderText,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    order.orderId,
                    style: const TextStyle(color: preorderMuted),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: preorderBorder),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _detail('Campaign', campaign.title),
                        _detail('Seller', campaign.sellerName),
                        const Divider(height: 24),
                        ...order.items.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 7),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${item.food.name} × ${item.quantity}',
                                  ),
                                ),
                                Text(formatMoney(item.lineTotal)),
                              ],
                            ),
                          ),
                        ),
                        const Divider(height: 24),
                        _amount('Food', order.subtotal),
                        _amount('Delivery', order.deliveryCharge),
                        _amount('Total', order.total, emphasized: true),
                        const SizedBox(height: 12),
                        _detail(
                          'Fulfilment',
                          sellerDelivery ? 'Seller delivery' : 'Pickup',
                        ),
                        _detail(
                          'When',
                          formatDateTime(
                            order.fulfilmentAt ?? campaign.fulfilmentAt,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (sellerDelivery) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'SocietyBites does not currently provide delivery services. '
                      'Delivery is arranged directly with the seller.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: preorderMuted,
                        fontSize: 12,
                        height: 1.4,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: preorderGreen,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: const Text(
                        'Done',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 82,
          child: Text(label, style: const TextStyle(color: preorderMuted)),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: preorderText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _amount(String label, double value, {bool emphasized = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: emphasized ? preorderText : preorderMuted,
                  fontWeight: emphasized ? FontWeight.w800 : FontWeight.w500,
                ),
              ),
            ),
            Text(
              formatMoney(value),
              style: TextStyle(
                color: preorderText,
                fontSize: emphasized ? 18 : 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );
}
