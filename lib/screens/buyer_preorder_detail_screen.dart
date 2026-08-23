import 'package:flutter/material.dart';

import '../models/data.dart';
import '../services/api_service.dart';
import '../widgets/preorder_widgets.dart';
import 'preorder_checkout_screen.dart';
import 'seller_storefront_screen.dart';

class BuyerPreOrderDetailScreen extends StatefulWidget {
  const BuyerPreOrderDetailScreen({
    super.key,
    required this.campaignId,
    this.initialCampaign,
    this.regularCartHasItems = false,
    this.cartItems,
    this.onCartChanged,
    this.onSellerTap,
  });

  final String campaignId;
  final PreOrderCampaign? initialCampaign;
  final bool regularCartHasItems;
  final List<CartItem>? cartItems;
  final VoidCallback? onCartChanged;
  final VoidCallback? onSellerTap;

  @override
  State<BuyerPreOrderDetailScreen> createState() =>
      _BuyerPreOrderDetailScreenState();
}

class _BuyerPreOrderDetailScreenState extends State<BuyerPreOrderDetailScreen> {
  PreOrderCampaign? _campaign;
  final Map<String, int> _quantities = {};
  late bool _loading;
  String? _error;

  @override
  void initState() {
    super.initState();
    _campaign = widget.initialCampaign;
    _loading = _campaign == null;
    _load();
  }

  Future<void> _load() async {
    if (_campaign == null && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final raw = await ApiService.getPreOrderCampaign(widget.campaignId);
      final campaign = PreOrderCampaign.fromJson(raw);
      if (!mounted) return;
      setState(() {
        _campaign = campaign;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = cleanApiError(e);
        _loading = false;
      });
    }
  }

  bool get _acceptingOrders {
    final campaign = _campaign;
    if (campaign == null || campaign.status != 'open') return false;
    final now = DateTime.now();
    return !now.isBefore(campaign.orderOpenAt) &&
        now.isBefore(campaign.orderCutoffAt);
  }

  bool get _upcoming {
    final campaign = _campaign;
    return campaign != null &&
        campaign.status == 'open' &&
        DateTime.now().isBefore(campaign.orderOpenAt);
  }

  int _quantity(PreOrderProduct product) => _quantities[product.listingId] ?? 0;

  void _changeQuantity(PreOrderProduct product, int delta) {
    if (!_acceptingOrders) return;
    final current = _quantity(product);
    final next = current + delta;
    if (next < 0) return;
    if (product.inventoryMode == 'limited' && next > product.quantity) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            product.quantity <= 0
                ? '${product.name} is sold out'
                : 'Only ${product.quantity} remaining for ${product.name}.',
          ),
        ),
      );
      return;
    }
    setState(() {
      if (next == 0) {
        _quantities.remove(product.listingId);
      } else {
        _quantities[product.listingId] = next;
      }
    });
  }

  double get _subtotal {
    final campaign = _campaign;
    if (campaign == null) return 0;
    return campaign.products.fold<double>(
      0,
      (sum, product) => sum + product.price * _quantity(product),
    );
  }

  int get _totalItems =>
      _quantities.values.fold<int>(0, (sum, quantity) => sum + quantity);

  Future<void> _continue() async {
    final campaign = _campaign;
    if (campaign == null || _totalItems == 0 || !_acceptingOrders) return;
    final selected = {
      for (final product in campaign.products)
        if (_quantity(product) > 0) product: _quantity(product),
    };
    final placed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            PreOrderCheckoutScreen(campaign: campaign, selectedItems: selected),
      ),
    );
    if (placed == true && mounted) {
      Navigator.pop(context, true);
    } else {
      await _load();
    }
  }

  void _openSeller() {
    if (widget.onSellerTap != null) {
      widget.onSellerTap!();
      return;
    }
    final campaign = _campaign;
    if (campaign == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SellerStorefrontScreen(
          seller: sellerFromPreOrderCampaign(campaign),
          cartItems: widget.cartItems,
          onCartChanged: widget.onCartChanged,
        ),
      ),
    );
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
          'Pre-order',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _campaign == null
          ? _loading
                ? const Center(
                    child: CircularProgressIndicator(color: preorderGreen),
                  )
                : _errorState()
          : RefreshIndicator(
              color: preorderGreen,
              onRefresh: _load,
              child: _content(),
            ),
      bottomNavigationBar: _campaign == null ? null : _bottomBar(),
    );
  }

  Widget _errorState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error!, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _load, child: const Text('Try again')),
        ],
      ),
    ),
  );

  Widget _content() {
    final campaign = _campaign!;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PreOrderCoverImage(
                  imageUrl: campaign.coverImageUrl,
                  width: double.infinity,
                  height: 220,
                  borderRadius: 20,
                ),
                const SizedBox(height: 16),
                const PreOrderBadge(),
                const SizedBox(height: 10),
                Text(
                  campaign.title,
                  style: const TextStyle(
                    color: preorderText,
                    fontSize: 28,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  formatReadyAt(campaign.fulfilmentAt),
                  style: const TextStyle(
                    color: preorderGreen,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatOrderByLabel(campaign.orderCutoffAt),
                  style: const TextStyle(
                    color: preorderMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                InkWell(
                  onTap: _openSeller,
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      'By ${campaign.sellerName}',
                      style: const TextStyle(
                        color: preorderGreen,
                        fontSize: 15,
                        decoration: TextDecoration.underline,
                        decorationColor: preorderGreen,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                if (campaign.description?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  Text(
                    campaign.description!,
                    style: const TextStyle(color: preorderMuted, height: 1.45),
                  ),
                ],
                const SizedBox(height: 18),
                _schedule(campaign),
                if (widget.regularCartHasItems) ...[
                  const SizedBox(height: 14),
                  _notice(
                    'Pre-orders must be placed separately from regular orders or orders from another seller. Your regular cart will remain unchanged.',
                    Icons.shopping_bag_outlined,
                  ),
                ],
                if (!_acceptingOrders) ...[
                  const SizedBox(height: 14),
                  _notice(
                    _upcoming
                        ? 'Ordering opens ${formatDateTime(campaign.orderOpenAt)}.'
                        : 'This pre-order is no longer accepting orders.',
                    Icons.info_outline_rounded,
                  ),
                ],
                const SizedBox(height: 24),
                const Text(
                  'CHOOSE PRODUCTS',
                  style: TextStyle(
                    color: preorderMuted,
                    fontSize: 11,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                ...campaign.products.map(_productCard),
                const SizedBox(height: 14),
                _fulfilmentInfo(campaign),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _schedule(PreOrderCampaign campaign) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: preorderBorder),
    ),
    child: Column(
      children: [
        _scheduleRow(
          Icons.lock_clock_outlined,
          'Order by',
          formatDateTime(campaign.orderCutoffAt),
        ),
        const Divider(height: 24),
        _scheduleRow(
          Icons.restaurant_rounded,
          'Fulfilment',
          formatDateTime(campaign.fulfilmentAt),
        ),
      ],
    ),
  );

  Widget _scheduleRow(IconData icon, String label, String value) => Row(
    children: [
      Icon(icon, color: preorderGreen, size: 21),
      const SizedBox(width: 12),
      SizedBox(
        width: 78,
        child: Text(label, style: const TextStyle(color: preorderMuted)),
      ),
      Expanded(
        child: Text(
          value,
          textAlign: TextAlign.right,
          style: const TextStyle(
            color: preorderText,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );

  Widget _productCard(PreOrderProduct product) {
    final quantity = _quantity(product);
    final limited = product.inventoryMode == 'limited';
    final soldOut = limited && product.quantity <= 0;
    final campaign = _campaign!;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: preorderBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F7F4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.restaurant_menu, color: preorderGreen),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PreOrderBadge(compact: true),
                    const SizedBox(height: 6),
                    Text(
                      product.name,
                      style: const TextStyle(
                        color: preorderText,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatMoney(product.price),
                      style: const TextStyle(
                        color: preorderGreen,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatReadyAt(campaign.fulfilmentAt),
                      style: const TextStyle(
                        color: preorderGreen,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatOrderByLabel(campaign.orderCutoffAt),
                      style: const TextStyle(
                        color: preorderMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      limited
                          ? soldOut
                                ? 'Sold out'
                                : '${product.quantity} remaining'
                          : 'Prepared based on pre-orders',
                      style: TextStyle(
                        color: soldOut
                            ? const Color(0xFFD94F4F)
                            : preorderMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: _quantityControl(product, quantity, soldOut),
          ),
        ],
      ),
    );
  }

  Widget _quantityControl(PreOrderProduct product, int quantity, bool soldOut) {
    if (quantity == 0) {
      return FilledButton(
        onPressed: soldOut || !_acceptingOrders
            ? null
            : () => _changeQuantity(product, 1),
        style: FilledButton.styleFrom(
          backgroundColor: preorderGreen,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFFE8EDEB),
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
        child: Text(
          soldOut ? 'Sold out' : 'Add to Pre-order',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _roundButton(
          Icons.remove,
          quantity > 0 ? () => _changeQuantity(product, -1) : null,
        ),
        SizedBox(
          width: 34,
          child: Text(
            '$quantity',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 17,
              color: preorderText,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        _roundButton(
          Icons.add,
          soldOut || !_acceptingOrders
              ? null
              : () => _changeQuantity(product, 1),
          filled: true,
        ),
      ],
    );
  }

  Widget _roundButton(
    IconData icon,
    VoidCallback? onTap, {
    bool filled = false,
  }) => IconButton(
    onPressed: onTap,
    visualDensity: VisualDensity.compact,
    style: IconButton.styleFrom(
      backgroundColor: filled ? preorderGreen : Colors.white,
      foregroundColor: filled ? Colors.white : preorderText,
      disabledBackgroundColor: const Color(0xFFE8EDEB),
      side: filled ? null : const BorderSide(color: Color(0xFFD4DBD8)),
    ),
    icon: Icon(icon, size: 18),
  );

  Widget _fulfilmentInfo(PreOrderCampaign campaign) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F7F4),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: const Color(0xFFD4E8DF)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'FULFILMENT OPTIONS',
          style: TextStyle(
            color: preorderGreen,
            fontSize: 11,
            letterSpacing: .8,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        if (campaign.offeredFulfilmentMethods.contains('pickup'))
          const Text('• Pickup from seller'),
        if (campaign.offeredFulfilmentMethods.contains('seller_delivery'))
          Text(
            '• Seller-arranged delivery — '
            '${formatMoney(campaign.defaultDeliveryCharge)} per order',
          ),
        const SizedBox(height: 8),
        const Text(
          'SocietyBites does not currently provide delivery services.',
          style: TextStyle(
            color: preorderMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _notice(String text, IconData icon) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF5EE),
      borderRadius: BorderRadius.circular(15),
      border: Border.all(color: const Color(0xFFFFE0CC)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: const Color(0xFFB85C3A), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF7A5A42),
              fontSize: 13,
              height: 1.4,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _bottomBar() => Material(
    color: Colors.white,
    child: SafeArea(
      top: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: preorderBorder)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_totalItems item${_totalItems == 1 ? '' : 's'}',
                    style: const TextStyle(color: preorderMuted, fontSize: 12),
                  ),
                  Text(
                    formatMoney(_subtotal),
                    style: const TextStyle(
                      color: preorderText,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _totalItems > 0 && _acceptingOrders
                    ? _continue
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: preorderGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                child: const Text(
                  'Continue Pre-order',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
