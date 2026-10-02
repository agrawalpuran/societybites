import 'dart:async';

import 'package:flutter/material.dart';
import '../web/web_breakpoints.dart';
import '../web/web_page_frame.dart';
import '../widgets/app_header.dart';
import '../widgets/listing_image.dart';
import '../widgets/order_fulfilment_banner.dart';
import '../widgets/order_timing_notice.dart';
import '../widgets/order_items_list.dart';
import '../widgets/order_status_tracker.dart';
import '../widgets/order_lifecycle_dialogs.dart';
import '../widgets/order_messages_button.dart';
import '../widgets/requested_ready_summary.dart';
import '../widgets/content_skeleton.dart';
import '../widgets/pull_refresh_gate.dart';
import '../widgets/status_banner.dart';
import '../models/data.dart';
import '../models/order_lifecycle.dart';
import '../services/api_service.dart';
import 'feedback_screen.dart';
import 'food_detail_screen.dart';
import 'seller_storefront_screen.dart';
import 'payment_screen.dart';

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

  /// Fired once when the first buyer-order load finishes,
  /// success or failure, so MainShell can continue sequential preload.
  final VoidCallback? onInitialLoadSettled;

  @override
  OrdersScreenState createState() => OrdersScreenState();
}

class OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _activeOrdersScroll = ScrollController();
  final _pullRefresh = PullRefreshGate();
  final _buyer = _RoleOrders(isLoading: true);
  bool _didNotifyInitialSettle = false;
  bool _ordersSlow = false;
  Timer? _ordersSlowTimer;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadOrders(isInitial: true);
  }

  bool get isLoadInProgress => _buyer.isLoading;
  bool get hasSuccessfullyLoaded => _buyer.hasSuccessfullyLoaded;

  /// Called by MainShell on failed first-load retry, app resume, and FCM.
  void refresh() => _loadOrders();

  /// Lightweight poll: refresh unread badges without spinner or campaign fetches.
  Future<void> refreshUnread() => _applyUnreadCounts();

  Future<void> _loadOrders({bool isInitial = false}) async {
    final bucket = _buyer;
    final showSpinner = !bucket.hasSuccessfullyLoaded;
    if (showSpinner) {
      _armSlowTimer();
      setState(() {
        bucket.isLoading = true;
        bucket.error = null;
      });
    }

    try {
      final fetch =
          widget.fetchOrders ??
          ({required String role}) => ApiService.getOrders(role: role);
      final orders = await fetch(role: 'buyer');
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

      _stopSlowTimer();
      setState(() {
        bucket.active = parsed.where((o) => o.isInBuyerActiveTab()).toList();
        bucket.past = parsed.where((o) => !o.isInBuyerActiveTab()).toList();
        bucket.isLoading = false;
        bucket.hasSuccessfullyLoaded = true;
        bucket.error = null;
      });
    } catch (e) {
      if (!mounted) return;

      if (!bucket.hasSuccessfullyLoaded) {
        _stopSlowTimer();
        setState(() {
          bucket.isLoading = false;
          bucket.error = ApiService.userFacingError(e);
        });
      }
    }
    if (isInitial) _notifyInitialLoadSettled();
  }

  Future<void> _applyUnreadCounts() async {
    if (!_buyer.hasSuccessfullyLoaded) return;
    try {
      final fetch =
          widget.fetchOrders ??
          ({required String role}) => ApiService.getOrders(role: role);
      final orders = await fetch(role: 'buyer');
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
      final nextActive = mapped(_buyer.active);
      final nextPast = mapped(_buyer.past);
      if (changed) {
        setState(() {
          _buyer.active = nextActive;
          _buyer.past = nextPast;
        });
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

  void _armSlowTimer() {
    _ordersSlowTimer?.cancel();
    _ordersSlow = false;
    _ordersSlowTimer = Timer(loadSlowThreshold, () {
      if (!mounted || !_buyer.isLoading) return;
      setState(() => _ordersSlow = true);
    });
  }

  void _stopSlowTimer() {
    _ordersSlowTimer?.cancel();
    _ordersSlow = false;
  }

  void _showActiveOrdersAtTop() {
    if (_tabController.index != 0) {
      _tabController.index = 0;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_activeOrdersScroll.hasClients) return;
      _activeOrdersScroll.jumpTo(0);
    });
  }

  @override
  void dispose() {
    _ordersSlowTimer?.cancel();
    _activeOrdersScroll.dispose();
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (useWebMarketplaceLayout(context)) return _buildWebOrders();
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'Manage your community kitchen favorites.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6A7774),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 14),
            _buildTabs(),
            const SizedBox(height: 16),
            _buildOrderBody(),
          ],
        ),
      ),
    );
  }

  Widget _buildWebOrders() {
    return Scaffold(
      backgroundColor: webPageBackground,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: webFrameMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(28, 28, 28, 0),
                child: Text(
                  'My Orders',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w800,
                    color: webInk,
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(28, 4, 28, 0),
                child: Text(
                  'Manage your community kitchen favorites.',
                  style: TextStyle(
                    fontSize: 15,
                    color: webMuted,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: _buildTabs(),
                ),
              ),
              const SizedBox(height: 16),
              _buildOrderBody(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrderBody() {
    final firstLoad = _buyer.isLoading && !_buyer.hasSuccessfullyLoaded;
    if (firstLoad) {
      return Expanded(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          children: [
            const KitchenOrdersSkeleton(),
            if (_ordersSlow)
              InlineLoadStatus.slow(
                id: 'buyer-orders',
                onRetry: () => _loadOrders(),
              ),
          ],
        ),
      );
    }
    if (_buyer.error != null && !_buyer.hasSuccessfullyLoaded) {
      return Expanded(
        child: Align(
          alignment: Alignment.topCenter,
          child: InlineLoadStatus.failed(
            id: 'buyer-orders',
            detail: _buyer.error,
            onRetry: () => _loadOrders(),
          ),
        ),
      );
    }
    return Expanded(
      child: TabBarView(
        controller: _tabController,
        children: [
          _ActiveTab(
            orders: _buyer.active,
            onRefresh: _loadOrders,
            onPull: () => _pullRefresh.run(_loadOrders),
            onReturnToTop: _showActiveOrdersAtTop,
            scrollController: _activeOrdersScroll,
            isSellerView: false,
          ),
          _PastTab(
            orders: _buyer.past,
            onRefresh: _loadOrders,
            onPull: () => _pullRefresh.run(_loadOrders),
            onExploreHome: widget.onExploreHome,
            isSellerView: false,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    if (useWebMarketplaceLayout(context)) return const SizedBox.shrink();
    return const AppHeader();
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
            Tab(text: 'Active (${_buyer.active.length})'),
            Tab(text: 'Past (${_buyer.past.length})'),
          ],
        ),
      ),
    );
  }
}

class _ActiveTab extends StatelessWidget {
  const _ActiveTab({
    required this.orders,
    required this.onRefresh,
    this.onPull,
    this.onReturnToTop,
    this.scrollController,
    this.isSellerView = false,
  });

  final List<Order> orders;
  final Future<void> Function() onRefresh;
  final Future<void> Function()? onPull;
  final VoidCallback? onReturnToTop;
  final ScrollController? scrollController;
  final bool isSellerView;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: StatusBanner(
          message: isSellerView ? 'No active sales.' : 'No active orders.',
        ),
      );
    }
    if (useWebMarketplaceLayout(context)) {
      return RefreshIndicator(
        color: const Color(0xFF0E5A47),
        onRefresh: onPull ?? onRefresh,
        child: ListView(
          controller: scrollController,
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
          children: [
            WebCardRows(
              children: [
                for (final order in orders)
                  !isSellerView && order.isTerminal
                      ? _PastOrderTile(order: order, onRefresh: onRefresh)
                      : _ActiveOrderCard(
                          order: order,
                          onRefresh: onRefresh,
                          onReturnToTop: onReturnToTop,
                          isSellerView: isSellerView,
                        ),
              ],
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      color: const Color(0xFF0E5A47),
      onRefresh: onPull ?? onRefresh,
      child: ListView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: orders
            .map(
              (o) => !isSellerView && o.isTerminal
                  ? _PastOrderTile(order: o, onRefresh: onRefresh)
                  : _ActiveOrderCard(
                      order: o,
                      onRefresh: onRefresh,
                      onReturnToTop: onReturnToTop,
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
    this.onReturnToTop,
    this.isSellerView = false,
    this.readOnly = false,
  });

  final Order order;
  final Future<void> Function() onRefresh;
  final VoidCallback? onReturnToTop;
  final bool isSellerView;
  final bool readOnly;

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
                order.isPreOrder
                    ? 'PRE-ORDER'
                    : order.isTerminal
                    ? 'ORDER DETAILS'
                    : 'ONGOING ORDER',
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
              Flexible(
                child: Text(
                  '${order.orderId} · ${order.placedAtLabel}',
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFFADB5B2),
                    fontWeight: FontWeight.w600,
                  ),
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
            RequestedReadySummary(order: order, isSellerView: isSellerView),
          ],
          const SizedBox(height: 12),
          OrderTotalRow(order: order),
          const SizedBox(height: 20),
          if (BuyerOrderLifecycle.displayedProgressStep(
                status: order.status,
                paymentStatus: order.paymentStatus,
                paymentMethod: order.paymentMethod,
              ) >=
              0)
            Align(
              alignment: Alignment.centerLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: OrderStatusTracker(
                  currentStep: BuyerOrderLifecycle.displayedProgressStep(
                    status: order.status,
                    paymentStatus: order.paymentStatus,
                    paymentMethod: order.paymentMethod,
                  ),
                  steps: _steps,
                ),
              ),
            ),
          if (!isSellerView &&
              !(BuyerOrderLifecycle.awaitingSellerPaymentConfirm(
                    paymentStatus: order.paymentStatus,
                    paymentMethod: order.paymentMethod,
                  ) &&
                  (order.status == 'accepted' ||
                      order.status == 'preparing'))) ...[
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
            if (!readOnly &&
                BuyerOrderLifecycle.canPayNow(
                  status: order.status,
                  paymentStatus: order.paymentStatus,
                  paymentMethod: order.paymentMethod,
                )) ...[
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    final result = await Navigator.push<Object?>(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PaymentScreen(order: order),
                      ),
                    );
                    if (!context.mounted) return;
                    if (result == true ||
                        result == PaymentScreen.returnToOrdersTop) {
                      await onRefresh();
                    }
                    if (result == PaymentScreen.returnToOrdersTop) {
                      onReturnToTop?.call();
                    }
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
            OrderMessagesButton(
              order: order,
              isSellerView: false,
              onClosed: onRefresh,
            ),
            const SizedBox(height: 10),
            if (!readOnly && order.canBuyerCancel) ...[
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

class _PastTab extends StatelessWidget {
  const _PastTab({
    required this.orders,
    required this.onRefresh,
    this.onPull,
    this.onExploreHome,
    this.isSellerView = false,
  });

  final List<Order> orders;
  final Future<void> Function() onRefresh;
  final Future<void> Function()? onPull;
  final VoidCallback? onExploreHome;
  final bool isSellerView;

  @override
  Widget build(BuildContext context) {
    if (useWebMarketplaceLayout(context)) return _buildWeb();
    return RefreshIndicator(
      color: const Color(0xFF0E5A47),
      onRefresh: onPull ?? onRefresh,
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
            StatusBanner(
              padding: const EdgeInsets.only(bottom: 16),
              message: isSellerView
                  ? 'No completed sales yet. When a buyer marks an order complete, it appears here.'
                  : 'No past orders yet.',
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

  Widget _buildWeb() {
    return RefreshIndicator(
      color: const Color(0xFF0E5A47),
      onRefresh: onPull ?? onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              isSellerView ? 'Past Sales' : 'Past Orders',
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: webInk,
              ),
            ),
          ),
          if (orders.isEmpty)
            StatusBanner(
              padding: const EdgeInsets.only(bottom: 16),
              message: isSellerView
                  ? 'No completed sales yet. When a buyer marks an order complete, it appears here.'
                  : 'No past orders yet.',
            )
          else
            WebCardRows(
              children: [
                for (final order in orders)
                  _PastOrderTile(
                    order: order,
                    onRefresh: onRefresh,
                    isSellerView: isSellerView,
                  ),
              ],
            ),
          const SizedBox(height: 20),
          if (!isSellerView) _ExploreBanner(onExploreHome: onExploreHome),
        ],
      ),
    );
  }
}

void _openBuyerOrderDetails({
  required BuildContext context,
  required Order order,
  required Future<void> Function() onRefresh,
}) {
  Navigator.push<void>(
    context,
    MaterialPageRoute(
      builder: (_) =>
          _BuyerOrderDetailScreen(order: order, onRefresh: onRefresh),
    ),
  );
}

class _BuyerOrderDetailScreen extends StatelessWidget {
  const _BuyerOrderDetailScreen({required this.order, required this.onRefresh});

  final Order order;
  final Future<void> Function() onRefresh;

  static const _webCardMaxWidth = 680.0;

  @override
  Widget build(BuildContext context) {
    if (useWebMarketplaceLayout(context)) return _buildWeb(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF7F8F7),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF101617),
        elevation: 0,
        title: Text(
          order.orderId,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        children: [
          _ActiveOrderCard(order: order, onRefresh: onRefresh, readOnly: true),
        ],
      ),
    );
  }

  Widget _buildWeb(BuildContext context) {
    return Scaffold(
      backgroundColor: webPageBackground,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: webFrameMaxWidth),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 28, 4),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'Back',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back_rounded, color: webInk),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        order.orderId,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: webInk,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
                  children: [
                    Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: _webCardMaxWidth,
                        ),
                        child: _ActiveOrderCard(
                          order: order,
                          onRefresh: onRefresh,
                          readOnly: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: isSellerView
              ? null
              : () => _openBuyerOrderDetails(
                  context: context,
                  order: order,
                  onRefresh: onRefresh,
                ),
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFEAEFED)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Multi-item orders list every dish below, so a hero
                    // thumbnail would just repeat the first one.
                    if (order.items.length == 1) ...[
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
                                ? '${order.orderId} • ${order.placedAtLabel}'
                                : '${order.sellerLabel} • ${order.placedAtLabel}',
                            style: const TextStyle(
                              fontSize: 13,
                              color: Color(0xFF8A9491),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (order.isPreOrder &&
                              order.fulfilmentAt != null) ...[
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF0F7F4),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'View details',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF0E5A47),
                          ),
                        ),
                      ),
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
          ),
        ),
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
