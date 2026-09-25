import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../widgets/listing_image.dart';
import '../widgets/order_fulfilment_banner.dart';
import '../widgets/order_timing_notice.dart';
import '../widgets/order_items_list.dart';
import '../widgets/order_lifecycle_dialogs.dart';
import '../widgets/order_messages_button.dart';
import '../widgets/requested_ready_summary.dart';
import '../models/data.dart';
import '../models/order_lifecycle.dart';
import '../services/api_service.dart';
import 'feedback_screen.dart';
import 'food_detail_screen.dart';
import 'seller_storefront_screen.dart';
import 'payment_screen.dart';
import 'tab_select_load.dart';

class _RoleOrders {
  List<Order> active = [];
  List<Order> past = [];
  bool isLoading;
  bool hasSuccessfullyLoaded = false;
  String? error;

  _RoleOrders({this.isLoading = false});
}

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({
    super.key,
    this.onExploreHome,
    this.fetchOrders,
    this.onInitialLoadSettled,
  });

  /// Switches to the home tab in the main shell (e.g. "Explore" CTA).
  final VoidCallback? onExploreHome;

  /// Test seam. Production uses [ApiService.getOrders].
  final Future<List<Map<String, dynamic>>> Function({required String role})?
      fetchOrders;

  /// Fired once when the first load of the default (Buying) role finishes,
  /// success or failure, so MainShell can continue sequential preload.
  final VoidCallback? onInitialLoadSettled;

  @override
  OrdersScreenState createState() => OrdersScreenState();
}

class OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _buyer = _RoleOrders(isLoading: true);
  final _seller = _RoleOrders();

  /// Buying = orders you placed; Selling = orders for your listings.
  bool _isSellingView = false;
  bool _didNotifyInitialSettle = false;

  _RoleOrders get _currentRole => _isSellingView ? _seller : _buyer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadOrders(isInitial: true);
  }

  bool get isLoadInProgress => _currentRole.isLoading;
  bool get hasSuccessfullyLoaded => _currentRole.hasSuccessfullyLoaded;

  /// Called by MainShell on failed first-load retry, app resume, and FCM.
  void refresh() => _loadOrders();

  /// Lightweight poll: refresh unread badges without spinner or campaign fetches.
  Future<void> refreshUnread() => _applyUnreadCounts();

  Future<void> _loadOrders({bool isInitial = false}) async {
    final selling = _isSellingView;
    final bucket = selling ? _seller : _buyer;
    final showSpinner = !bucket.hasSuccessfullyLoaded;
    if (showSpinner) {
      setState(() {
        bucket.isLoading = true;
        bucket.error = null;
      });
    }

    try {
      final fetch = widget.fetchOrders ??
          ({required String role}) => ApiService.getOrders(role: role);
      final orders = await fetch(role: selling ? 'seller' : 'buyer');
      var parsed = orders.map(Order.fromJson).toList();
      final campaignIds = parsed
          .where((order) => order.isPreOrder && order.campaignId != null)
          .map((order) => order.campaignId!)
          .toSet();
      if (campaignIds.isNotEmpty) {
        final campaigns = <String, PreOrderCampaign>{};
        await Future.wait(
          campaignIds.map((id) async {
            try {
              campaigns[id] = PreOrderCampaign.fromJson(
                await ApiService.getPreOrderCampaign(id),
              );
            } catch (_) {
              // Order history still works if campaign metadata cannot refresh.
            }
          }),
        );
        parsed = parsed
            .map(
              (order) =>
                  order.campaignId != null &&
                      campaigns.containsKey(order.campaignId)
                  ? order.withCampaign(campaigns[order.campaignId]!)
                  : order,
            )
            .toList();
      }

      if (!mounted) return;

      setState(() {
        if (selling) {
          bucket.active = parsed.where((o) => !o.isTerminal).toList();
          bucket.past = parsed.where((o) => o.isTerminal).toList();
        } else {
          bucket.active = parsed.where((o) => o.isInBuyerActiveTab()).toList();
          bucket.past = parsed.where((o) => !o.isInBuyerActiveTab()).toList();
        }
        bucket.isLoading = false;
        bucket.hasSuccessfullyLoaded = true;
        bucket.error = null;
      });
    } catch (e) {
      if (!mounted) return;

      if (!bucket.hasSuccessfullyLoaded) {
        setState(() {
          bucket.isLoading = false;
          bucket.error = e.toString();
        });
      }
    }
    if (isInitial) _notifyInitialLoadSettled();
  }

  Future<void> _applyUnreadCounts() async {
    if (!_buyer.hasSuccessfullyLoaded && !_seller.hasSuccessfullyLoaded) return;
    try {
      final fetch = widget.fetchOrders ??
          ({required String role}) => ApiService.getOrders(role: role);
      final roles = <bool>[];
      if (_buyer.hasSuccessfullyLoaded) roles.add(false);
      if (_seller.hasSuccessfullyLoaded) roles.add(true);
      for (final selling in roles) {
        final bucket = selling ? _seller : _buyer;
        final orders = await fetch(role: selling ? 'seller' : 'buyer');
        final counts = <String, int>{};
        for (final json in orders) {
          final parsed = Order.fromJson(json);
          counts[parsed.id] = parsed.unreadMessageCount;
        }
        if (!mounted) return;
        var changed = false;
        List<Order> mapped(List<Order> list) => list.map((order) {
          final next = counts[order.id] ?? 0;
          if (next == order.unreadMessageCount) return order;
          changed = true;
          return order.withUnreadCount(next);
        }).toList();
        final nextActive = mapped(bucket.active);
        final nextPast = mapped(bucket.past);
        if (changed) {
          setState(() {
            bucket.active = nextActive;
            bucket.past = nextPast;
          });
        }
      }
    } catch (_) {}
  }

  void _notifyInitialLoadSettled() {
    if (_didNotifyInitialSettle) return;
    _didNotifyInitialSettle = true;
    final callback = widget.onInitialLoadSettled;
    if (callback == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback();
    });
  }

  void _selectRole({required bool selling}) {
    if (_isSellingView == selling) return;
    final bucket = selling ? _seller : _buyer;
    final shouldFetch = shouldFetchOnTabSelect(
      hasSuccessfullyLoaded: bucket.hasSuccessfullyLoaded,
      isLoadInProgress: bucket.isLoading,
    );
    setState(() {
      _isSellingView = selling;
      if (shouldFetch) {
        bucket.isLoading = true;
        bucket.error = null;
      }
    });
    if (shouldFetch) {
      _loadOrders();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 18),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'My Orders',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101617),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                _isSellingView
                    ? 'Orders from neighbors for your kitchen.'
                    : 'Manage your community kitchen favorites.',
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6A7774),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 14),
            _buildRoleToggle(),
            const SizedBox(height: 14),
            _buildTabs(),
            const SizedBox(height: 16),
            if (_currentRole.isLoading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
                ),
              )
            else if (_currentRole.error != null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _currentRole.error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Color(0xFFD94F4F)),
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _ActiveTab(
                      orders: _currentRole.active,
                      onRefresh: _loadOrders,
                      isSellerView: _isSellingView,
                    ),
                    _PastTab(
                      orders: _currentRole.past,
                      onRefresh: _loadOrders,
                      onExploreHome: widget.onExploreHome,
                      isSellerView: _isSellingView,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return const AppHeader();
  }

  Widget _buildRoleToggle() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F2F1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: _RoleChip(
                label: 'Buying',
                selected: !_isSellingView,
                onTap: () => _selectRole(selling: false),
              ),
            ),
            Expanded(
              child: _RoleChip(
                label: 'Selling',
                selected: _isSellingView,
                onTap: () => _selectRole(selling: true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F2F1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: TabBar(
          controller: _tabController,
          indicator: BoxDecoration(
            color: const Color(0xFF0E5A47),
            borderRadius: BorderRadius.circular(12),
          ),
          indicatorSize: TabBarIndicatorSize.tab,
          dividerHeight: 0,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFF6A7774),
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
          tabs: [
            Tab(text: 'Active (${_currentRole.active.length})'),
            Tab(text: 'Past (${_currentRole.past.length})'),
          ],
        ),
      ),
    );
  }
}

class _RoleChip extends StatelessWidget {
  const _RoleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(3),
      child: Material(
        color: selected ? const Color(0xFF0E5A47) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
                color: selected ? Colors.white : const Color(0xFF6A7774),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActiveTab extends StatelessWidget {
  const _ActiveTab({
    required this.orders,
    required this.onRefresh,
    this.isSellerView = false,
  });

  final List<Order> orders;
  final Future<void> Function() onRefresh;
  final bool isSellerView;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(
        child: Text(
          isSellerView ? 'No active sales.' : 'No active orders.',
          style: const TextStyle(color: Color(0xFF6A7774)),
        ),
      );
    }
    return RefreshIndicator(
      color: const Color(0xFF0E5A47),
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: orders
            .map(
              (o) => !isSellerView && o.isTerminal
                  ? _PastOrderTile(
                      order: o,
                      onRefresh: onRefresh,
                    )
                  : _ActiveOrderCard(
                      order: o,
                      onRefresh: onRefresh,
                      isSellerView: isSellerView,
                    ),
            )
            .toList(),
      ),
    );
  }
}

class _ActiveOrderCard extends StatelessWidget {
  const _ActiveOrderCard({
    required this.order,
    required this.onRefresh,
    this.isSellerView = false,
  });

  final Order order;
  final Future<void> Function() onRefresh;
  final bool isSellerView;

  static const _steps = BuyerOrderLifecycle.progressSteps;

  String get _paymentLabel {
    switch (order.paymentStatus) {
      case 'buyer_marked_paid':
        return 'Awaiting Seller Confirmation';
      case 'seller_confirmed':
      case 'paid':
        return 'Payment Received ✓';
      default:
        return 'Payment Pending';
    }
  }

  Color get _paymentColor {
    switch (order.paymentStatus) {
      case 'seller_confirmed':
      case 'paid':
        return const Color(0xFF0E5A47);
      case 'buyer_marked_paid':
        return const Color(0xFFB8860B);
      default:
        return const Color(0xFFD94F4F);
    }
  }

  Color get _paymentBg {
    switch (order.paymentStatus) {
      case 'seller_confirmed':
      case 'paid':
        return const Color(0xFFE8F5EE);
      case 'buyer_marked_paid':
        return const Color(0xFFFFF8E8);
      default:
        return const Color(0xFFFFF0F0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                order.isPreOrder ? 'PRE-ORDER' : 'ONGOING ORDER',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: order.isPreOrder
                      ? const Color(0xFFB85C3A)
                      : const Color(0xFF8A9491),
                ),
              ),
              const Spacer(),
              Text(
                order.orderId,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFFADB5B2),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          if (order.isPreOrder) ...[
            const SizedBox(height: 10),
            Text(
              order.campaignTitle ?? 'Pre-order campaign',
              style: const TextStyle(
                fontSize: 17,
                color: Color(0xFF101617),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              '${order.sellerLabel} · '
              '${order.fulfilmentAt == null ? 'Fulfilment scheduled' : Order.formatReadyBy(order.fulfilmentAt!)}',
              style: const TextStyle(
                color: Color(0xFF6A7774),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: _paymentBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              _paymentLabel,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _paymentColor,
              ),
            ),
          ),
          if (isSellerView) ...[
            const SizedBox(height: 10),
            Text(
              order.buyerLabel,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF3A4644),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 14),
          OrderFulfilmentBanner(order: order, isSellerView: isSellerView),
          OrderItemsList(items: order.items),
          if (order.requestedReadyAt != null) ...[
            const SizedBox(height: 10),
            RequestedReadySummary(
              order: order,
              isSellerView: isSellerView,
            ),
          ],
          const SizedBox(height: 12),
          OrderTotalRow(order: order),
          const SizedBox(height: 20),
          if (BuyerOrderLifecycle.progressStep(order.status) >= 0)
            _StatusTracker(
              currentStep: BuyerOrderLifecycle.progressStep(order.status),
              steps: _steps,
            ),
          if (!isSellerView) ...[
            const SizedBox(height: 12),
            Text(
              BuyerOrderLifecycle.headline(order.status),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF101617),
              ),
            ),
            if (BuyerOrderLifecycle.detail(order.status) != null) ...[
              const SizedBox(height: 2),
              Text(
                BuyerOrderLifecycle.detail(order.status)!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6A7774),
                ),
              ),
            ],
          ],
          if (order.showExpectedReadyAt) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7F4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD4E8DF)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.schedule_rounded,
                    size: 18,
                    color: Color(0xFF0E5A47),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      order.requestedReadyAt != null
                          ? 'Seller confirmed ready by:\n${Order.formatNeedBy(order.expectedReadyAt!)}'
                          : 'Ready by ${Order.formatReadyBy(order.expectedReadyAt!)}',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0E5A47),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          if (isSellerView) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7F4),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFD4E8DF)),
              ),
              child: const Text(
                'Manage this sale on Dashboard — accept, reject, mark ready, and complete.',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF3A4644),
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
              ),
            ),
          ] else ...[
            if (BuyerOrderLifecycle.canPayNow(
              status: order.status,
              paymentStatus: order.paymentStatus,
              paymentMethod: order.paymentMethod,
            )) ...[
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PaymentScreen(order: order),
                      ),
                    );
                    if (result == true) await onRefresh();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE85D04),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  icon: const Icon(Icons.payment_rounded, size: 18),
                  label: const Text(
                    'Pay Now',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            OrderTimingNotice(
              foods: order.items.map((item) => item.food),
              preOrderFulfilmentAt: order.fulfilmentAt,
            ),
            const SizedBox(height: 10),
            order.isPreOrder
                ? _PreOrderFulfilmentCard(order: order)
                : _PickupInfoCard(order: order),
            const SizedBox(height: 10),
            OrderMessagesButton(
              order: order,
              isSellerView: false,
              onClosed: onRefresh,
            ),
            const SizedBox(height: 10),
            if (order.canBuyerCancel) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        scrollable: true,
                        title: const Text('Cancel order?'),
                        content: Text(order.buyerCancelConfirmMessage),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Keep order'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            style: TextButton.styleFrom(
                              foregroundColor: const Color(0xFFD94F4F),
                            ),
                            child: const Text('Cancel order'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true || !context.mounted) return;
                    try {
                      await ApiService.updateOrderStatus(
                        orderId: order.id.isNotEmpty ? order.id : order.orderId,
                        status: 'cancelled',
                      );
                    } catch (e) {
                      if (!context.mounted) return;
                      final raw = e.toString().toLowerCase();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            raw.contains('cutoff')
                                ? 'Pre-orders can no longer be cancelled because the order cutoff has passed.'
                                : ApiService.userFacingError(e),
                          ),
                        ),
                      );
                      return;
                    }
                    try {
                      await onRefresh();
                    } catch (_) {}
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Order cancelled'),
                        backgroundColor: Color(0xFF0E5A47),
                      ),
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFFE8B4B4)),
                    foregroundColor: const Color(0xFFD94F4F),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.cancel_outlined, size: 18),
                  label: const Text(
                    'Cancel Order',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

class _PickupInfoCard extends StatelessWidget {
  const _PickupInfoCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final food = order.food;
    final location = food.locationLabel;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7F6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(
                Icons.place_outlined,
                size: 16,
                color: Color(0xFF0E5A47),
              ),
              const SizedBox(width: 5),
              const Text(
                'Pickup details',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101617),
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  order.sellerLabel,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF3A4644),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Where',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF6A7774),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  location,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.25,
                    color: Color(0xFF3A4644),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreOrderFulfilmentCard extends StatelessWidget {
  const _PreOrderFulfilmentCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final sellerDelivery = order.fulfilmentMethod == 'seller_delivery';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F7F4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD4E8DF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                sellerDelivery
                    ? Icons.delivery_dining_outlined
                    : Icons.shopping_bag_outlined,
                color: const Color(0xFF0E5A47),
                size: 21,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  sellerDelivery
                      ? 'Seller-arranged delivery'
                      : 'Pickup from seller',
                  style: const TextStyle(
                    color: Color(0xFF0E5A47),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (order.fulfilmentAt != null) ...[
            const SizedBox(height: 6),
            Text(
              Order.formatReadyBy(order.fulfilmentAt!),
              style: const TextStyle(
                color: Color(0xFF3A4644),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (sellerDelivery) ...[
            const SizedBox(height: 6),
            const Text(
              'SocietyBites does not provide delivery. Coordinate directly with the seller.',
              style: TextStyle(
                color: Color(0xFF6A7774),
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusTracker extends StatelessWidget {
  const _StatusTracker({required this.currentStep, required this.steps});
  final int currentStep;
  final List<String> steps;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(steps.length * 2 - 1, (i) {
        if (i.isOdd) {
          final stepBefore = i ~/ 2;
          final isDone = stepBefore < currentStep;
          return Expanded(
            child: Container(
              height: 2,
              color: isDone ? const Color(0xFF0E5A47) : const Color(0xFFD4DBD8),
            ),
          );
        }
        final stepIndex = i ~/ 2;
        final isActive = stepIndex <= currentStep;
        final isCurrent = stepIndex == currentStep;

        return Column(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive
                    ? const Color(0xFF0E5A47)
                    : const Color(0xFFF0F2F1),
                border: isCurrent
                    ? Border.all(color: const Color(0xFF0E5A47), width: 2)
                    : null,
              ),
              child: isActive
                  ? Icon(
                      isCurrent
                          ? Icons.restaurant_rounded
                          : Icons.check_rounded,
                      size: 14,
                      color: Colors.white,
                    )
                  : null,
            ),
            const SizedBox(height: 4),
            Text(
              steps[stepIndex],
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: isActive
                    ? const Color(0xFF0E5A47)
                    : const Color(0xFF8A9491),
              ),
            ),
          ],
        );
      }),
    );
  }
}

class _PastTab extends StatelessWidget {
  const _PastTab({
    required this.orders,
    required this.onRefresh,
    this.onExploreHome,
    this.isSellerView = false,
  });

  final List<Order> orders;
  final Future<void> Function() onRefresh;
  final VoidCallback? onExploreHome;
  final bool isSellerView;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: const Color(0xFF0E5A47),
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              isSellerView ? 'Past Sales' : 'Past Orders',
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: Color(0xFF101617),
              ),
            ),
          ),
        if (orders.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              isSellerView
                  ? 'No completed sales yet. When a buyer marks an order complete, it appears here.'
                  : 'No past orders yet.',
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF6A7774),
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          )
        else
          ...orders.map(
            (o) => _PastOrderTile(
              order: o,
              onRefresh: onRefresh,
              isSellerView: isSellerView,
            ),
          ),
        const SizedBox(height: 20),
        if (!isSellerView) _ExploreBanner(onExploreHome: onExploreHome),
        ],
      ),
    );
  }
}

class _PastOrderTile extends StatelessWidget {
  const _PastOrderTile({
    required this.order,
    required this.onRefresh,
    this.isSellerView = false,
  });

  final Order order;
  final Future<void> Function() onRefresh;
  final bool isSellerView;

  @override
  Widget build(BuildContext context) {
    final isCancelled = order.status == 'cancelled';
    final isRejected = order.status == 'rejected';
    final statusLabel = isRejected
        ? 'ORDER REJECTED'
        : isCancelled
        ? 'CANCELLED'
        : 'COMPLETED';
    final statusBg = isRejected || isCancelled
        ? const Color(0xFFFFF0F0)
        : const Color(0xFFE8F5EE);
    final statusFg = isRejected || isCancelled
        ? const Color(0xFFD94F4F)
        : const Color(0xFF0E5A47);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (order.items.isNotEmpty) ...[
                ListingImage(
                  food: order.items.first.food,
                  width: 52,
                  height: 52,
                  borderRadius: 14,
                  iconSize: 26,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (order.isPreOrder)
                      Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFE5D6),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          'PRE-ORDER',
                          style: TextStyle(
                            color: Color(0xFFB85C3A),
                            fontSize: 10,
                            letterSpacing: .6,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    Text(
                      order.campaignTitle ?? order.itemsSummary,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101617),
                      ),
                    ),
                    if (isSellerView && order.items.length == 1) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Qty ${order.items.first.quantity}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6A7774),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 3),
                    Text(
                      isSellerView
                          ? '${order.orderId} • ${order.date}'
                          : '${order.sellerLabel} • ${order.date}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF8A9491),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (order.isPreOrder && order.fulfilmentAt != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        'Fulfilment ${Order.formatReadyBy(order.fulfilmentAt!)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF0E5A47),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    if (isSellerView) ...[
                      const SizedBox(height: 4),
                      Text(
                        order.buyerLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF3A4644),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Text(
                '₹${order.total.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101617),
                ),
              ),
            ],
          ),
          if (order.items.length > 1) ...[
            const SizedBox(height: 12),
            OrderItemsList(
              items: order.items,
              compact: true,
              showSellerName: !isSellerView,
            ),
          ],
          const SizedBox(height: 10),
          if (isSellerView) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: statusFg,
                ),
              ),
            ),
            if (isRejected) OrderRejectReasonBlock(order: order),
          ] else ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: statusBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 0.6,
                  fontWeight: FontWeight.w700,
                  color: statusFg,
                ),
              ),
            ),
            if (isRejected) OrderRejectReasonBlock(order: order),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (order.status == 'completed' && !order.hasReview)
                  GestureDetector(
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FeedbackScreen(
                            food: order.food,
                            orderId: order.id,
                          ),
                        ),
                      );
                      onRefresh();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F7F6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Rate\nExperience',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF3A4644),
                          height: 1.2,
                        ),
                      ),
                    ),
                  )
                else if (order.status == 'completed' && order.hasReview)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5EE),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                      'Reviewed ✓',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0E5A47),
                      ),
                    ),
                  ),
                if (!isCancelled && !isRejected)
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => FoodDetailScreen(
                            food: order.food,
                            onSellerTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => SellerStorefrontScreen(
                                    seller: sellerFromListing(order.food),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE5D6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Order\nAgain',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFB85C3A),
                          height: 1.2,
                        ),
                      ),
                    ),
                  ),
                OrderMessagesButton(
                  order: order,
                  isSellerView: false,
                  inline: true,
                  onClosed: onRefresh,
                ),
              ],
            ),
          ],
          if (isSellerView) ...[
            const SizedBox(height: 10),
            OrderMessagesButton(
              order: order,
              isSellerView: true,
              onClosed: onRefresh,
            ),
          ],
        ],
      ),
    );
  }
}

class _ExploreBanner extends StatelessWidget {
  const _ExploreBanner({this.onExploreHome});

  final VoidCallback? onExploreHome;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFF5EE), Color(0xFFFEECE0)],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Hungry for\nsomething new?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2A1A0A),
              height: 1.15,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Discover talented home cooks in your\n'
            'neighborhood and support local food\nenthusiasts.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF7A5A42),
              fontWeight: FontWeight.w500,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 46,
            child: ElevatedButton(
              onPressed: () {
                if (onExploreHome != null) {
                  onExploreHome!();
                } else {
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0E5A47),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 22),
              ),
              child: const Text(
                'Explore Neighborhood',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
