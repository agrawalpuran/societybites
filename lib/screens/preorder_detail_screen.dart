import 'package:flutter/material.dart';

import '../models/data.dart';
import '../services/api_service.dart';
import '../widgets/order_items_list.dart';
import '../widgets/preorder_widgets.dart';
import 'create_preorder_screen.dart';

class PreOrderDetailScreen extends StatefulWidget {
  const PreOrderDetailScreen({
    super.key,
    required this.campaignId,
    this.promptToAddProduct = false,
  });

  final String campaignId;
  final bool promptToAddProduct;

  @override
  State<PreOrderDetailScreen> createState() => _PreOrderDetailScreenState();
}

class _PreOrderDetailScreenState extends State<PreOrderDetailScreen> {
  PreOrderCampaign? _campaign;
  PreOrderSummary? _summary;
  List<Order> _orders = [];
  bool _loading = true;
  bool _updating = false;
  String? _error;
  bool _promptShown = false;

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
      final results = await Future.wait([
        ApiService.getPreOrderCampaign(widget.campaignId),
        ApiService.getPreOrderSummary(widget.campaignId),
        ApiService.getPreOrderOrders(widget.campaignId),
      ]);
      final campaign = PreOrderCampaign.fromJson(
        Map<String, dynamic>.from(results[0] as Map),
      );
      final summary = PreOrderSummary.fromJson(
        Map<String, dynamic>.from(results[1] as Map),
      );
      final orders = (results[2] as List<Map<String, dynamic>>)
          .map(Order.fromJson)
          .toList();
      if (!mounted) return;
      setState(() {
        _campaign = campaign;
        _summary = summary;
        _orders = orders;
        _loading = false;
      });
      if (widget.promptToAddProduct &&
          !_promptShown &&
          campaign.products.isEmpty) {
        _promptShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _addProduct());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = cleanApiError(e);
        _loading = false;
      });
    }
  }

  Future<void> _addProduct() async {
    final campaign = _campaign;
    if (campaign == null || campaign.status == 'cancelled') return;
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddPreOrderProductScreen(
          campaignId: campaign.id,
          existingProductNames: campaign.products
              .map((p) => p.name.toLowerCase())
              .toSet(),
        ),
      ),
    );
    if (added == true) {
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Product added to the campaign'),
            backgroundColor: preorderGreen,
          ),
        );
      }
    }
  }

  Future<void> _editCampaign() async {
    final campaign = _campaign;
    if (campaign == null) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreatePreOrderScreen(
          campaign: campaign,
          hasOrders: _orders.isNotEmpty,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _editProduct(PreOrderProduct product) async {
    if (_campaign == null || _orders.isNotEmpty) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddPreOrderProductScreen(
          campaignId: _campaign!.id,
          existingProductNames: _campaign!.products
              .where((item) => item.listingId != product.listingId)
              .map((item) => item.name.toLowerCase())
              .toSet(),
          product: product,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _changeStatus(String status) async {
    final campaign = _campaign;
    if (campaign == null || _updating) return;
    final verb = status == 'open'
        ? 'open'
        : status == 'closed'
        ? 'close orders for'
        : 'cancel';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${verb[0].toUpperCase()}${verb.substring(1)} campaign?'),
        content: Text(
          status == 'closed'
              ? 'Buyers will no longer be able to place new orders. Existing orders and production quantities remain available.'
              : status == 'cancelled'
              ? 'This draft will be cancelled. This action does not cancel or refund individual orders.'
              : 'Buyers can order once the opening time is reached and until the cutoff.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep as is'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: status == 'cancelled'
                  ? const Color(0xFFD94F4F)
                  : preorderGreen,
            ),
            child: Text(status == 'closed' ? 'Close orders' : 'Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _updating = true);
    try {
      await ApiService.updatePreOrderCampaign(id: campaign.id, status: status);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'open'
                  ? 'Campaign opened'
                  : status == 'closed'
                  ? 'Orders closed'
                  : 'Campaign cancelled',
            ),
            backgroundColor: preorderGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(cleanApiError(e))));
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
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
          'Pre-order details',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: preorderGreen))
          : _error != null
          ? _errorState()
          : RefreshIndicator(
              color: preorderGreen,
              onRefresh: _load,
              child: _content(),
            ),
    );
  }

  Widget _errorState() {
    return Center(
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
  }

  Widget _content() {
    final campaign = _campaign!;
    final summary = _summary!;
    final displayStatus = campaignDisplayStatus(campaign);
    final demandHeading = productionHeading(
      status: displayStatus,
      orderCutoffAt: summary.orderCutoffAt,
    );
    final showingCurrentDemand = demandHeading == 'CURRENT DEMAND';
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PreOrderCoverImage(
                  imageUrl: campaign.coverImageUrl,
                  width: double.infinity,
                  height: 220,
                  borderRadius: 20,
                ),
                const SizedBox(height: 18),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        campaign.title,
                        style: const TextStyle(
                          fontSize: 28,
                          height: 1.15,
                          fontWeight: FontWeight.w800,
                          color: preorderText,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    PreOrderStatusBadge(status: displayStatus),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: _editCampaign,
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text(
                      'Edit Campaign',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                if (_orders.isNotEmpty)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF5EE),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: const Text(
                      'Some campaign settings and existing products are locked because buyers have already placed orders.',
                      style: TextStyle(
                        color: Color(0xFF7A5A42),
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (campaign.description?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 10),
                  Text(
                    campaign.description!,
                    style: const TextStyle(
                      color: preorderMuted,
                      height: 1.4,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
                if (campaign.fulfilmentNotes?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F7F4),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      'Fulfilment notes: ${campaign.fulfilmentNotes}',
                      style: const TextStyle(
                        color: preorderText,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _scheduleCard(campaign),
                const SizedBox(height: 22),
                _sectionTitle('SUMMARY'),
                const SizedBox(height: 10),
                _summaryGrid(summary),
                const SizedBox(height: 12),
                _fulfilmentCard(summary),
                const SizedBox(height: 24),
                _sectionTitle(demandHeading),
                const SizedBox(height: 5),
                Text(
                  showingCurrentDemand
                      ? 'Updates as buyers place or cancel orders.'
                      : 'Use these backend-calculated totals for preparation.',
                  style: const TextStyle(
                    color: preorderMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 12),
                _productionCard(summary),
                const SizedBox(height: 24),
                Row(
                  children: [
                    const Expanded(child: _StaticSectionTitle('PRODUCTS')),
                    if (campaign.status != 'cancelled')
                      TextButton.icon(
                        onPressed: _addProduct,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Add product'),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (campaign.products.isEmpty)
                  PreOrderEmptyState(
                    title: 'Add your first product',
                    message:
                        'Choose one of your listings and set campaign price and availability.',
                    action: ElevatedButton.icon(
                      onPressed: _addProduct,
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add product'),
                    ),
                  )
                else
                  ...campaign.products.map(_productTile),
                const SizedBox(height: 24),
                _sectionTitle('ORDERS'),
                const SizedBox(height: 10),
                if (_orders.isEmpty)
                  const PreOrderEmptyState(
                    title: 'No orders yet',
                    message:
                        'Individual buyer orders will appear here after the campaign opens.',
                  )
                else
                  ..._orders.map(_orderCard),
                const SizedBox(height: 24),
                _deliveryNotice(),
                const SizedBox(height: 20),
                _actions(campaign, summary),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _scheduleCard(PreOrderCampaign campaign) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: preorderBorder),
      ),
      child: Column(
        children: [
          _iconRow(
            Icons.lock_clock_outlined,
            'Order cutoff',
            formatDateTime(campaign.orderCutoffAt),
          ),
          const Divider(height: 24),
          _iconRow(
            Icons.restaurant_rounded,
            'Fulfilment',
            formatDateTime(campaign.fulfilmentAt),
          ),
        ],
      ),
    );
  }

  Widget _iconRow(IconData icon, String label, String value) => Row(
    children: [
      Icon(icon, color: preorderGreen, size: 21),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(color: preorderMuted)),
            const SizedBox(height: 2),
            Text(
              value,
              style: const TextStyle(
                color: preorderText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _summaryGrid(PreOrderSummary summary) {
    return Row(
      children: [
        Expanded(child: _metric('${summary.totalOrders}', 'Orders')),
        const SizedBox(width: 10),
        Expanded(child: _metric('${summary.totalItems}', 'Items')),
        const SizedBox(width: 10),
        Expanded(
          child: _metric(formatMoney(summary.foodSubtotal), 'Food value'),
        ),
      ],
    );
  }

  Widget _metric(String value, String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: preorderBorder),
    ),
    child: Column(
      children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: preorderText,
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: preorderMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    ),
  );

  Widget _fulfilmentCard(PreOrderSummary summary) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F7F4),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFD4E8DF)),
    ),
    child: Row(
      children: [
        Expanded(
          child: _fulfilmentMetric(
            Icons.shopping_bag_outlined,
            'Pickup',
            summary.pickupOrders,
          ),
        ),
        Container(width: 1, height: 38, color: const Color(0xFFD4E8DF)),
        Expanded(
          child: _fulfilmentMetric(
            Icons.delivery_dining_outlined,
            'Seller delivery',
            summary.sellerDeliveryOrders,
          ),
        ),
      ],
    ),
  );

  Widget _fulfilmentMetric(IconData icon, String label, int count) => Column(
    children: [
      Icon(icon, color: preorderGreen),
      const SizedBox(height: 4),
      Text(
        '$label: $count',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: preorderText,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    ],
  );

  Widget _productionCard(PreOrderSummary summary) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: preorderBorder),
      ),
      child: summary.products.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(18),
              child: Text('Add products to start tracking demand.'),
            )
          : Column(
              children: summary.products.asMap().entries.map((entry) {
                final item = entry.value;
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.productName,
                              style: const TextStyle(
                                color: preorderText,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '${item.quantityToPrepare}',
                            style: const TextStyle(
                              fontSize: 22,
                              color: preorderGreen,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (entry.key < summary.products.length - 1)
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  ],
                );
              }).toList(),
            ),
    );
  }

  Widget _productTile(PreOrderProduct product) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: preorderBorder),
    ),
    child: Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFF0F7F4),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.restaurant_menu, color: preorderGreen),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.name,
                style: const TextStyle(
                  color: preorderText,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                product.inventoryMode == 'limited'
                    ? 'Limited to ${product.quantity}'
                    : 'Prepare based on orders',
                style: const TextStyle(color: preorderMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        Text(
          formatMoney(product.price),
          style: const TextStyle(
            color: preorderText,
            fontWeight: FontWeight.w800,
          ),
        ),
        if (_orders.isEmpty)
          IconButton(
            onPressed: () => _editProduct(product),
            tooltip: 'Edit product',
            icon: const Icon(Icons.edit_outlined, color: preorderGreen),
          ),
      ],
    ),
  );

  Widget _orderCard(Order order) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: preorderBorder),
    ),
    child: InkWell(
      onTap: () => _showOrder(order),
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.orderId,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: preorderText,
                    ),
                  ),
                ),
                _smallBadge(order.status),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              order.buyerName?.trim().isNotEmpty == true
                  ? order.buyerName!
                  : 'Neighbor',
              style: const TextStyle(
                color: preorderMuted,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            ...order.items.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '${item.food.name} × ${item.quantity}',
                  style: const TextStyle(
                    color: preorderText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  order.fulfilmentMethod == 'seller_delivery'
                      ? Icons.delivery_dining_outlined
                      : Icons.shopping_bag_outlined,
                  size: 17,
                  color: preorderGreen,
                ),
                const SizedBox(width: 6),
                Text(
                  order.fulfilmentMethod == 'seller_delivery'
                      ? 'Seller delivery'
                      : 'Pickup',
                  style: const TextStyle(
                    color: preorderGreen,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const Spacer(),
                Text(
                  formatMoney(order.total),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: preorderText,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFFADB5B2),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  void _showOrder(Order order) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.72,
        minChildSize: 0.45,
        maxChildSize: 0.92,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.orderId,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _smallBadge(order.status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              order.buyerLabel,
              style: const TextStyle(color: preorderMuted),
            ),
            if (order.buyerPhone?.isNotEmpty == true)
              Text(
                order.buyerPhone!,
                style: const TextStyle(color: preorderMuted),
              ),
            const Divider(height: 28),
            OrderItemsList(items: order.items),
            const Divider(height: 24),
            _moneyRow('Food subtotal', order.subtotal),
            if (order.deliveryCharge > 0)
              _moneyRow('Seller delivery charge', order.deliveryCharge),
            _moneyRow('Total', order.total, emphasized: true),
            const SizedBox(height: 16),
            _detailRow(
              'Fulfilment',
              order.fulfilmentMethod == 'seller_delivery'
                  ? 'Seller-arranged delivery'
                  : 'Pickup',
            ),
            _detailRow('Order status', order.status.replaceAll('_', ' ')),
            _detailRow(
              'Payment status',
              order.paymentStatus.replaceAll('_', ' '),
            ),
          ],
        ),
      ),
    );
  }

  Widget _moneyRow(String label, double amount, {bool emphasized = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
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
              formatMoney(amount),
              style: TextStyle(
                color: preorderText,
                fontSize: emphasized ? 18 : 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      );

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 110,
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

  Widget _smallBadge(String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFFF0F2F1),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      value.replaceAll('_', ' ').toUpperCase(),
      style: const TextStyle(
        color: preorderMuted,
        fontSize: 10,
        letterSpacing: 0.5,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _deliveryNotice() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF5EE),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFFFE0CC)),
    ),
    child: const Text(
      'SocietyBites does not currently provide delivery services. Pickup or '
      'seller-arranged delivery is coordinated directly with the seller.',
      style: TextStyle(
        color: Color(0xFF7A5A42),
        fontSize: 13,
        height: 1.4,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _actions(PreOrderCampaign campaign, PreOrderSummary summary) {
    final status = campaignDisplayStatus(campaign);
    if (status == 'open') {
      return SizedBox(
        width: double.infinity,
        height: 50,
        child: OutlinedButton.icon(
          onPressed: _updating ? null : () => _changeStatus('closed'),
          icon: const Icon(Icons.lock_outline_rounded),
          label: const Text(
            'Close orders',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFD94F4F),
            side: const BorderSide(color: Color(0xFFE8B4B4)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
          ),
        ),
      );
    }
    if (status == 'draft') {
      return Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: campaign.products.isEmpty || _updating
                  ? null
                  : () => _changeStatus('open'),
              icon: const Icon(Icons.campaign_rounded),
              label: Text(
                campaign.products.isEmpty
                    ? 'Add a product before opening'
                    : 'Open campaign',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: preorderGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
              ),
            ),
          ),
          if (summary.totalOrders == 0) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _updating ? null : () => _changeStatus('cancelled'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFD94F4F),
              ),
              child: const Text('Cancel draft'),
            ),
          ],
        ],
      );
    }
    return const SizedBox.shrink();
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 12,
      letterSpacing: 1.2,
      color: preorderMuted,
      fontWeight: FontWeight.w800,
    ),
  );
}

class _StaticSectionTitle extends StatelessWidget {
  const _StaticSectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        letterSpacing: 1.2,
        color: preorderMuted,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}
