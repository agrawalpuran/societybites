import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../widgets/listing_image.dart';
import '../widgets/order_items_list.dart';
import '../widgets/order_fulfilment_banner.dart';
import '../models/data.dart';
import '../models/kitchen_order_category.dart';
import '../models/order_lifecycle.dart';
import '../models/seller_order_history.dart';
import '../services/api_service.dart';
import '../widgets/order_lifecycle_dialogs.dart';
import '../services/seller_onboarding.dart';
import '../services/session_service.dart';
import '../widgets/preorder_widgets.dart';
import '../widgets/order_messages_button.dart';
import '../widgets/profile_menu_tile.dart';
import '../widgets/simple_time_picker.dart';
import '../widgets/requested_ready_summary.dart';
import '../widgets/seller_insights_panel.dart';
import '../widgets/screen_loading_note.dart';
import '../widgets/status_banner.dart';
import 'add_listing_screen.dart';
import 'add_listing_type_screen.dart';
import 'my_listings_screen.dart';
import 'preorder_detail_screen.dart';
import 'seller_preorders_screen.dart';
import 'seller_feedback_screen.dart';
import 'seller_older_orders_screen.dart';

class SellerDashboardScreen extends StatefulWidget {
  const SellerDashboardScreen({
    super.key,
    this.onInitialLoadSettled,
    this.onKitchenAttentionCount,
    this.onListingCreated,
    this.onStartSelling,
    this.fetchOrders,
    this.fetchCampaigns,
  });

  /// Fired once when the first orders load finishes (success or failure).
  final VoidCallback? onInitialLoadSettled;

  /// Pending seller orders that still need accept/reject.
  final ValueChanged<int>? onKitchenAttentionCount;

  /// Returns the main shell to Home after a new regular listing is created.
  final VoidCallback? onListingCreated;

  /// First-time selling from My Kitchen. Production uses MainShell.
  final VoidCallback? onStartSelling;

  /// Test seam. Production uses [ApiService.getOrders].
  final Future<List<Map<String, dynamic>>> Function()? fetchOrders;

  /// Test seam. Production uses [ApiService.getPreOrderCampaigns].
  final Future<List<Map<String, dynamic>>> Function()? fetchCampaigns;

  @override
  SellerDashboardScreenState createState() => SellerDashboardScreenState();
}

class SellerDashboardScreenState extends State<SellerDashboardScreen> {
  List<Order> _activeOrders = [];
  List<Order> _pastOrders = [];
  bool _hasOlderPast = false;
  bool _hasOlderActive = false;
  int _pendingAttentionCount = 0;
  bool _isLoading = true;
  bool _hasSuccessfullyLoaded = false;
  String? _error;
  Map<String, dynamic> _stats = {};
  List<PreOrderCampaign> _preOrderCampaigns = [];
  bool _preOrdersLoading = true;
  bool _didNotifyInitialSettle = false;
  int _ordersLoadGen = 0;
  bool _ordersRefreshInFlight = false;

  /// 0 = Orders, 1 = Dashboard. Orders is the default My Kitchen landing tab.
  int _areaTab = 0;

  /// 0 = Active, 1 = Past
  int _ordersTab = 0;

  KitchenOrderCategory? _kitchenFilter;
  String? _role;
  bool _roleLoaded = false;

  bool get _canSell => _role == 'seller' || _role == 'super_admin';

  @override
  void initState() {
    super.initState();
    _loadRole();
    _loadOrders();
    _loadStats();
    _loadPreOrders();
  }

  bool get isLoadInProgress => _isLoading || _ordersRefreshInFlight;
  bool get hasSuccessfullyLoaded => _hasSuccessfullyLoaded;

  /// Called by MainShell on failed first-load retry, app resume, and FCM.
  void refresh() {
    _loadRole();
    _loadOrders();
    _loadStats();
    _loadPreOrders();
  }

  /// Lightweight poll: refresh unread badges without a full kitchen reload.
  Future<void> refreshUnread() async {
    if (!_hasSuccessfullyLoaded) return;
    try {
      final List<Map<String, dynamic>> raw;
      final injected = widget.fetchOrders;
      if (injected != null) {
        raw = await injected();
      } else {
        final pages = await Future.wait([
          ApiService.getSellerOrderBucket(scope: 'active'),
          ApiService.getSellerOrderBucket(scope: 'recent_past'),
        ]);
        raw = [...pages[0].orders, ...pages[1].orders];
      }
      final counts = <String, int>{};
      for (final json in raw) {
        final parsed = Order.fromJson(json);
        counts[parsed.id] = parsed.unreadMessageCount;
      }
      if (!mounted) return;
      var changed = false;
      List<Order> mapped(List<Order> list) => list.map((order) {
        final next = counts[order.id] ?? order.unreadMessageCount;
        if (next == order.unreadMessageCount) return order;
        changed = true;
        return order.withUnreadCount(next);
      }).toList();
      final nextActive = mapped(_activeOrders);
      final nextPast = mapped(_pastOrders);
      if (!changed) return;
      setState(() {
        _activeOrders = nextActive;
        _pastOrders = nextPast;
      });
    } catch (_) {}
  }

  /// Bottom-nav entry into My Kitchen always lands on seller orders.
  void showKitchenOrders() {
    _loadRole();
    if (!mounted || _areaTab == 0) return;
    setState(() => _areaTab = 0);
  }

  Future<void> _loadRole() async {
    final role = await SessionService.getRole();
    if (!mounted) return;
    if (_roleLoaded && role == _role) return;
    setState(() {
      _role = role;
      _roleLoaded = true;
    });
  }

  Future<void> _startSelling() async {
    if (widget.onStartSelling != null) {
      widget.onStartSelling!();
      return;
    }
    try {
      final enabled = await SellerOnboarding.startSelling(context);
      if (!enabled || !mounted) return;
      await _loadRole();
      await _refreshDashboard();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not enable selling: $error')),
      );
    }
  }

  List<KitchenOrderCategory> get _visibleKitchenCategories =>
      visibleKitchenCategories(
        orders: _activeOrders,
        campaigns: _preOrderCampaigns,
      );

  KitchenOrderCategory? get _resolvedKitchenCategory => resolveKitchenCategory(
        visible: _visibleKitchenCategories,
        selected: _kitchenFilter,
      );

  List<Order> _ordersForCategory(List<Order> source) {
    return ordersForKitchenCategory(
      source: source,
      selected: _resolvedKitchenCategory,
      visible: _visibleKitchenCategories,
    );
  }

  int _actionCountForCategory(KitchenOrderCategory category) {
    return kitchenCategoryActionCount(
      category: category,
      orders: _activeOrders,
      visible: _visibleKitchenCategories,
      needsAction: (order) => orderNeedsSellerAction(
        status: order.status,
        paymentStatus: order.paymentStatus,
        paymentMethod: order.paymentMethod,
      ),
    );
  }

  int get _activeActionCount => _ordersForCategory(_activeOrders)
      .where(
        (order) => orderNeedsSellerAction(
          status: order.status,
          paymentStatus: order.paymentStatus,
          paymentMethod: order.paymentMethod,
        ),
      )
      .length;

  bool get _showPreOrdersSection {
    final visible = _visibleKitchenCategories;
    if (!visible.contains(KitchenOrderCategory.preorders)) return false;
    if (visible.length <= 1) return true;
    return _resolvedKitchenCategory == KitchenOrderCategory.preorders;
  }

  bool get _showKitchenOrderList {
    if (_resolvedKitchenCategory != KitchenOrderCategory.preorders) {
      return true;
    }
    if (_ordersForCategory(_activeOrders).isNotEmpty ||
        _ordersForCategory(_pastOrders).isNotEmpty) {
      return true;
    }
    return _preOrderCampaigns.isEmpty;
  }

  Future<void> _loadPreOrders() async {
    try {
      List<Map<String, dynamic>> raw;
      final injected = widget.fetchCampaigns;
      if (injected != null) {
        raw = await injected();
      } else {
        final societyId = await SessionService.getSocietyId();
        if (societyId == null || societyId.isEmpty) {
          if (mounted) {
            setState(() {
              _preOrderCampaigns = [];
              _preOrdersLoading = false;
            });
          }
          return;
        }
        final sellerId = await SessionService.getUserId();
        if (sellerId == null) return;
        raw = await ApiService.getPreOrderCampaigns(
          societyId: societyId,
          sellerId: sellerId,
        );
      }
      final campaigns = await Future.wait(
        raw.map((json) async {
          final campaign = PreOrderCampaign.fromJson(json);
          if (injected != null) return campaign;
          try {
            final summary = PreOrderSummary.fromJson(
              await ApiService.getPreOrderSummary(campaign.id),
            );
            return PreOrderCampaign(
              id: campaign.id,
              title: campaign.title,
              description: campaign.description,
              coverImageUrl: campaign.coverImageUrl,
              status: summary.status,
              orderOpenAt: campaign.orderOpenAt,
              orderCutoffAt: campaign.orderCutoffAt,
              fulfilmentAt: campaign.fulfilmentAt,
              offeredFulfilmentMethods: campaign.offeredFulfilmentMethods,
              defaultDeliveryCharge: campaign.defaultDeliveryCharge,
              products: campaign.products,
              totalOrders: summary.totalOrders,
              totalItems: summary.totalItems,
              foodSubtotal: summary.foodSubtotal,
            );
          } catch (_) {
            return campaign;
          }
        }),
      );
      campaigns.removeWhere((campaign) => !campaignShowsInKitchen(campaign));
      campaigns.sort((a, b) {
        const rank = {'open': 0, 'draft': 1, 'closed': 2};
        final statusCompare = (rank[campaignDisplayStatus(a)] ?? 3).compareTo(
          rank[campaignDisplayStatus(b)] ?? 3,
        );
        return statusCompare != 0
            ? statusCompare
            : a.fulfilmentAt.compareTo(b.fulfilmentAt);
      });
      if (!mounted) return;
      setState(() {
        _preOrderCampaigns = campaigns.take(2).toList();
        _preOrdersLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _preOrdersLoading = false);
    }
  }

  Future<void> _createPreOrderCatalog() async {
    final canList = await SellerOnboarding.ensureCanCreateListing(context);
    if (!canList || !mounted) return;
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddListingScreen(
          catalogType: listingCatalogPreorder,
        ),
      ),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Catalog item saved. Add it to a campaign when you are ready.',
          ),
        ),
      );
    }
  }

  Future<void> _refreshDashboard() async {
    await Future.wait([_loadOrders(), _loadPreOrders(), _loadStats()]);
  }

  Future<void> _loadStats() async {
    try {
      final stats = await ApiService.getSellerStats();
      if (!mounted) return;
      setState(() => _stats = stats);
    } catch (_) {}
  }

  Future<void> _loadOrders() async {
    final gen = ++_ordersLoadGen;
    final showSpinner = !_hasSuccessfullyLoaded;
    _ordersRefreshInFlight = true;
    if (showSpinner) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    } else if (mounted) {
      setState(() => _error = null);
    }

    try {
      late final List<Order> active;
      late final List<Order> past;
      var hasOlderPast = false;
      var hasOlderActive = false;
      var pendingAttention = 0;
      final injected = widget.fetchOrders;
      if (injected != null) {
        final parsed = (await injected()).map(Order.fromJson).toList();
        active = parsed
            .where(
              (order) => isSellerRecentOpenOrder(
                isTerminal: order.isTerminal,
                createdAt: order.createdAt,
              ),
            )
            .toList();
        past = parsed
            .where(
              (order) => isSellerRecentPastOrder(
                isTerminal: order.isTerminal,
                completedAt: order.completedAt,
                cancelledAt: order.cancelledAt,
                rejectedAt: order.rejectedAt,
                createdAt: order.createdAt,
              ),
            )
            .toList();
        hasOlderPast = parsed.any(
          (order) =>
              order.isTerminal &&
              !isSellerRecentPastOrder(
                isTerminal: order.isTerminal,
                completedAt: order.completedAt,
                cancelledAt: order.cancelledAt,
                rejectedAt: order.rejectedAt,
                createdAt: order.createdAt,
              ),
        );
        hasOlderActive = parsed.any(
          (order) =>
              !order.isTerminal &&
              !isSellerRecentOpenOrder(
                isTerminal: order.isTerminal,
                createdAt: order.createdAt,
              ),
        );
        pendingAttention =
            parsed.where((order) => order.status == 'pending').length;
      } else {
        final pages = await Future.wait([
          ApiService.getSellerOrderBucket(scope: 'active'),
          ApiService.getSellerOrderBucket(scope: 'recent_past'),
        ]);
        active = pages[0].orders.map(Order.fromJson).toList();
        past = pages[1].orders.map(Order.fromJson).toList();
        hasOlderActive = pages[0].hasOlder;
        hasOlderPast = pages[1].hasOlder;
        pendingAttention = pages[0].pendingCount;
      }

      if (!mounted || gen != _ordersLoadGen) return;

      setState(() {
        _activeOrders = active;
        _pastOrders = past;
        _hasOlderPast = hasOlderPast;
        _hasOlderActive = hasOlderActive;
        _pendingAttentionCount = pendingAttention;
        _isLoading = false;
        _hasSuccessfullyLoaded = true;
        _ordersRefreshInFlight = false;
      });
      _publishKitchenAttention();
      _loadStats();
    } catch (e) {
      if (!mounted || gen != _ordersLoadGen) return;

      setState(() {
        _error = e.toString();
        _isLoading = false;
        _ordersRefreshInFlight = false;
      });
    }
    _notifyInitialLoadSettled();
  }

  void _upsertOrder(Order updated) {
    if (!mounted) return;
    _ordersLoadGen++;
    setState(() {
      if (updated.isTerminal) {
        _activeOrders =
            _activeOrders.where((order) => order.id != updated.id).toList();
        _pastOrders = [
          updated,
          ..._pastOrders.where((order) => order.id != updated.id),
        ];
        return;
      }
      _pastOrders =
          _pastOrders.where((order) => order.id != updated.id).toList();
      final index =
          _activeOrders.indexWhere((order) => order.id == updated.id);
      if (index >= 0) {
        final next = [..._activeOrders];
        next[index] = updated;
        _activeOrders = next;
      } else {
        _activeOrders = [updated, ..._activeOrders];
      }
    });
    _publishKitchenAttention();
  }

  void _publishKitchenAttention() {
    widget.onKitchenAttentionCount?.call(_pendingAttentionCount);
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

  Future<void> _updateStatus(Order order, String nextStatus) async {
    debugPrint(
      'SELLER STATUS ${order.orderId} ${order.status} → $nextStatus via ${ApiService.baseUrl}',
    );
    try {
      final json = await ApiService.advanceOrderStatus(
        orderId: order.id,
        currentStatus: order.status,
        nextStatus: nextStatus,
      );
      if (!mounted) return;

      _upsertOrder(Order.fromJson(json));
      unawaited(_loadOrders());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
          content: Text('Order updated to ${_statusLabel(nextStatus)}'),
          backgroundColor: const Color(0xFF0E5A47),
        ),
      );

      // Optional Ready-by: COD keeps current accept-time picker. UPI waits for payment confirm.
      if (nextStatus == 'accepted') {
        final payment = SellerPaymentActions.fromOrder(
          status: nextStatus,
          paymentMethod: order.paymentMethod,
          paymentStatus: order.paymentStatus,
        );
        if (payment.promptReadyByOnAccept) {
          await _promptReadyBy(order.id, order.orderId);
        }
      }
    } catch (e) {
      debugPrint('SELLER STATUS FAILED ${order.orderId}: $e');
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 88),
          content: Text('Could not update order: $e'),
        ),
      );
    }
  }

  Future<void> _promptReadyBy(String orderId, String orderNumber) async {
    final result = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ReadyBySheet(orderId: orderNumber, allowClear: false),
    );

    if (!mounted || result == null || result == 'skip') return;

    await _applyReadyBy(orderId, result);
  }

  Future<void> _editReadyBy(Order order) async {
    final result = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ReadyBySheet(
        orderId: order.orderId,
        allowClear: order.expectedReadyAt != null,
        initial: order.expectedReadyAt,
      ),
    );

    if (!mounted || result == null || result == 'skip') return;

    await _applyReadyBy(order.id, result);
  }

  Future<void> _applyReadyBy(String orderId, Object result) async {
    try {
      if (result == 'clear') {
        await ApiService.setOrderReadyTime(
          orderId: orderId,
          expectedReadyAt: null,
        );
      } else if (result is DateTime) {
        await ApiService.setOrderReadyTime(
          orderId: orderId,
          expectedReadyAt: result,
        );
      } else if (result is num) {
        await ApiService.setOrderReadyTime(
          orderId: orderId,
          readyInMinutes: result,
        );
      } else {
        return;
      }
      await _loadOrders();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == 'clear'
                ? 'Ready by estimate removed'
                : 'Ready by updated',
          ),
          backgroundColor: const Color(0xFF0E5A47),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not update Ready by: $e')));
    }
  }

  bool _isRejecting = false;
  String? _rejectingOrderId;

  Future<void> _rejectOrder(Order order) async {
    if (_isRejecting) return;
    final result = await confirmRejectOrder(context);
    if (result == null || !mounted) return;

    _isRejecting = true;
    setState(() => _rejectingOrderId = order.id);
    try {
      final json = await ApiService.rejectOrder(
        orderId: order.id,
        reason: result.reason,
        otherText: result.note,
      );
      if (mounted) _upsertOrder(Order.fromJson(json));
      await _loadOrders();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Order rejected'),
          backgroundColor: Color(0xFFD94F4F),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not reject order: $e')));
    } finally {
      _isRejecting = false;
      if (mounted) setState(() => _rejectingOrderId = null);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'preparing':
        return 'Accepted';
      case 'ready':
        return 'Ready for pickup';
      case 'picked_up':
        return 'Ready for pickup';
      case 'completed':
        return 'Completed';
      case 'cancelled':
        return 'Cancelled';
      case 'rejected':
        return 'Rejected';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      body: SafeArea(
        child: Column(
          children: [
            const AppHeader(),
            if (_roleLoaded && !_canSell)
              Expanded(child: _buildBuyerStartSelling())
            else ...[
            _buildAreaTabs(),
            Expanded(
              child: IndexedStack(
                index: _areaTab,
                children: [
                  RefreshIndicator(
                    color: const Color(0xFF0E5A47),
                    onRefresh: _refreshDashboard,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      slivers: [
                        SliverToBoxAdapter(child: _buildOrdersHeader()),
                        SliverToBoxAdapter(child: _buildKitchenTypeSelector()),
                        if (_showPreOrdersSection)
                          SliverToBoxAdapter(child: _buildPreOrdersSection()),
                        if (_error != null)
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                _error!,
                                style: const TextStyle(color: Color(0xFFD94F4F)),
                              ),
                            ),
                          ),
                        if (_isLoading)
                          const SliverToBoxAdapter(
                            child: ScreenLoadingNote(
                              message: 'Loading orders…',
                            ),
                          )
                        else if (_showKitchenOrderList)
                          SliverToBoxAdapter(child: _buildOrdersSection(context)),
                        SliverToBoxAdapter(child: _buildExpandCard()),
                        SliverToBoxAdapter(child: _buildAddListingCta(context)),
                        const SliverToBoxAdapter(child: SizedBox(height: 30)),
                      ],
                    ),
                  ),
                  RefreshIndicator(
                    color: const Color(0xFF0E5A47),
                    onRefresh: _refreshDashboard,
                    child: CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(
                        parent: BouncingScrollPhysics(),
                      ),
                      slivers: [
                        SliverToBoxAdapter(child: _buildDashboardHeader()),
                        SliverToBoxAdapter(child: _buildSatisfactionRow()),
                        SliverToBoxAdapter(
                          child: SellerInsightsPanel(
                            showHeading: false,
                            onSeeAllOrders: () => setState(() => _areaTab = 0),
                          ),
                        ),
                        const SliverToBoxAdapter(child: SizedBox(height: 30)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBuyerStartSelling() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 32),
      children: [
        const Text(
          'My Kitchen',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w800,
            color: Color(0xFF101617),
          ),
        ),
        const SizedBox(height: 16),
        StatusBanner(
          padding: EdgeInsets.zero,
          title: 'Start selling homemade food',
          message:
              'List food for neighbors in your society. Next you will complete Seller Settings.',
          action: FilledButton(
            key: const Key('my-kitchen-start-selling'),
            onPressed: _startSelling,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0E5A47),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Start Selling'),
          ),
        ),
      ],
    );
  }

  Widget _buildAreaTabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        height: 46,
        decoration: BoxDecoration(
          color: const Color(0xFFF0F2F1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: _OrdersSegment(
                key: const Key('seller-area-orders-tab'),
                label: 'Orders',
                selected: _areaTab == 0,
                badgeCount: _pendingAttentionCount,
                badgeKey: const Key('seller-area-orders-badge'),
                onTap: () => setState(() => _areaTab = 0),
              ),
            ),
            Expanded(
              child: _OrdersSegment(
                key: const Key('seller-area-dashboard-tab'),
                label: 'Dashboard',
                selected: _areaTab == 1,
                onTap: () => setState(() => _areaTab = 1),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDashboardHeader() {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Dashboard',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
          SizedBox(height: 4),
          Text(
            'How your kitchen performed in this period.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF6A7774),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Orders',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101617),
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Accept, prepare, and complete neighbor orders.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6A7774),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            alignment: WrapAlignment.end,
            children: [
              TextButton(
                key: const Key('my-kitchen-add-listing'),
                onPressed: _openAddListing,
                child: const Text(
                  'Add listing',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              TextButton(
                key: const Key('my-kitchen-listings'),
                onPressed: _openMyListings,
                child: const Text(
                  'My Listings',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKitchenTypeSelector() {
    final cats = _visibleKitchenCategories;
    if (cats.length <= 1) return const SizedBox.shrink();
    final selected = _resolvedKitchenCategory;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: SizedBox(
        height: 44,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFFF0F2F1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scroll = cats.length > 2 && constraints.maxWidth < 360;
              final itemWidth = scroll
                  ? 128.0
                  : constraints.maxWidth / cats.length;
              final row = Row(
                children: [
                  for (final category in cats)
                    SizedBox(
                      width: itemWidth,
                      child: _OrdersSegment(
                        key: ValueKey('kitchen-type-${category.name}'),
                        label: kitchenCategoryLabel(category),
                        selected: selected == category,
                        badgeCount: _actionCountForCategory(category),
                        badgeKey:
                            ValueKey('kitchen-type-badge-${category.name}'),
                        onTap: () => setState(() => _kitchenFilter = category),
                      ),
                    ),
                ],
              );
              if (!scroll) return row;
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: row,
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildSatisfactionRow() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: _SatisfactionCard(
        rating: (_stats['avgRating'] as num?)?.toDouble() ?? 0,
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const SellerFeedbackScreen(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPreOrdersSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pre-orders',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: preorderText,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Plan ahead and track what to prepare.',
                      style: TextStyle(
                        fontSize: 13,
                        color: preorderMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const SellerPreOrdersScreen(),
                    ),
                  );
                  _loadPreOrders();
                },
                child: const Text(
                  'View all',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('create-preorder-catalog'),
              onPressed: _createPreOrderCatalog,
              style: OutlinedButton.styleFrom(
                foregroundColor: preorderGreen,
                side: const BorderSide(color: Color(0xFFD4E8DF)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: const Text(
                'Create catalog',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_preOrdersLoading)
            const ScreenLoadingNote(message: 'Loading pre-orders…')
          else if (_preOrderCampaigns.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7F4),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFD4E8DF)),
              ),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'No pre-order campaigns yet.',
                      style: TextStyle(
                        color: preorderMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SellerPreOrdersScreen(),
                        ),
                      );
                      _loadPreOrders();
                    },
                    child: const Text('Create'),
                  ),
                ],
              ),
            )
          else
            ..._preOrderCampaigns.map(
              (campaign) => PreOrderCampaignCard(
                campaign: campaign,
                compact: true,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          PreOrderDetailScreen(campaignId: campaign.id),
                    ),
                  );
                  _loadPreOrders();
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOrdersSection(BuildContext context) {
    final showingPast = _ordersTab == 1;
    final active = _ordersForCategory(_activeOrders);
    final past = _ordersForCategory(_pastOrders);
    final orders = showingPast ? past : active;
    final typedEmpty = _visibleKitchenCategories.length > 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F2F1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _OrdersSegment(
                    label: 'Active (${active.length})',
                    selected: !showingPast,
                    badgeCount: _activeActionCount,
                    badgeKey: const Key('kitchen-active-badge'),
                    onTap: () => setState(() => _ordersTab = 0),
                  ),
                ),
                Expanded(
                  child: _OrdersSegment(
                    label: 'Past (${past.length})',
                    selected: showingPast,
                    onTap: () => setState(() => _ordersTab = 1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if ((showingPast && past.isNotEmpty) ||
              (!showingPast && active.isNotEmpty && _hasOlderActive))
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'RECENT ORDERS',
                key: Key('recent-orders-heading'),
                style: TextStyle(
                  fontSize: 12,
                  letterSpacing: 0.7,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF6A7774),
                ),
              ),
            ),
          if (orders.isEmpty)
            StatusBanner(
              padding: EdgeInsets.zero,
              message: showingPast
                  ? (typedEmpty
                      ? 'No orders yet. Orders for this type will appear here when buyers place them.'
                      : _hasOlderPast
                      ? 'No recent orders'
                      : 'No past orders yet. Completed and cancelled sales will appear here.')
                  : (typedEmpty
                      ? 'No orders yet. Orders for this type will appear here when buyers place them.'
                      : _hasOlderActive
                      ? 'No recent orders'
                      : 'No active orders yet. When neighbors order your food, they show up here.'),
            )
          else if (showingPast)
            ...orders.map(
              (order) => SellerPastOrderCard(
                order: order,
                onRefresh: _loadOrders,
              ),
            )
          else
            ...orders.map(
              (order) => SellerActiveOrderCard(
                key: ValueKey(order.id),
                order: order,
                onAction: _updateStatus,
                onOrderUpdated: _upsertOrder,
                onPaymentConfirmed: _loadOrders,
                onReject: _rejectOrder,
                onReadyBy: _editReadyBy,
                rejectBusy: _rejectingOrderId == order.id,
              ),
            ),
          if (showingPast && _hasOlderPast) ...[
            const SizedBox(height: 8),
            KeyedSubtree(
              key: const Key('older-orders-row'),
              child: ProfileMenuTile(
                icon: Icons.history_rounded,
                title: 'Older Orders',
                subtitle: 'Orders older than 7 days',
                onTap: () => _openOlderOrders(openOrders: false),
              ),
            ),
          ],
          if (!showingPast && _hasOlderActive) ...[
            const SizedBox(height: 8),
            KeyedSubtree(
              key: const Key('older-open-orders-row'),
              child: ProfileMenuTile(
                icon: Icons.history_rounded,
                title: 'Older Orders',
                subtitle: 'Still in progress, older than 7 days',
                onTap: () => _openOlderOrders(openOrders: true),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openOlderOrders({required bool openOrders}) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SellerOlderOrdersScreen(
          openOrders: openOrders,
          fetchOrders: widget.fetchOrders,
          onOrderRefresh: _loadOrders,
          onAction: openOrders ? _updateStatus : null,
          onOrderUpdated: openOrders ? _upsertOrder : null,
          onPaymentConfirmed: openOrders ? _loadOrders : null,
          onReject: openOrders ? _rejectOrder : null,
          onReadyBy: openOrders ? _editReadyBy : null,
        ),
      ),
    );
    if (mounted) await _loadOrders();
  }

  Widget _buildExpandCard() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFFE8F5EE), Color(0xFFD4EDDF)],
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Want to expand?',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0A4638),
                height: 1.15,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Join our "Pro Kitchen" program and\nreach 5x more neighbors with\nshared delivery logistics.',
              style: TextStyle(
                fontSize: 13,
                color: Color(0xFF3A6B56),
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('This feature is coming soon'),
                    ),
                  );
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF0E5A47), width: 1.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                ),
                child: const Text(
                  'Upgrade Account',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: Color(0xFF0E5A47),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openMyListings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const MyListingsScreen()),
    );
    if (mounted) _loadOrders();
  }

  Future<void> _openAddListing() async {
    final canList = await SellerOnboarding.ensureCanCreateListing(context);
    if (!canList || !mounted) return;

    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const AddListingTypeScreen()),
    );
    if (created == true && mounted) {
      _loadOrders();
      widget.onListingCreated?.call();
    }
  }

  Widget _buildAddListingCta(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _openMyListings,
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF0E5A47),
                side: const BorderSide(color: Color(0xFF0E5A47)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              icon: const Icon(Icons.inventory_2_outlined, size: 20),
              label: const Text(
                'My Listings',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 58,
            child: ElevatedButton.icon(
              onPressed: _openAddListing,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0E5A47),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                elevation: 0,
              ),
              icon: const Icon(Icons.add_rounded, size: 22),
              label: const Text(
                'Add New Listing',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SatisfactionCard extends StatelessWidget {
  const _SatisfactionCard({this.rating = 0, this.onTap});

  final double rating;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFEAEFED)),
          ),
          child: Row(
            children: [
              const Icon(Icons.star_rounded, color: Colors.amber, size: 22),
              const SizedBox(width: 8),
              Text(
                rating > 0 ? '${rating.toString()}/5' : '—/5',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101617),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Satisfaction Score',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6A7774),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const Text(
                'View feedback',
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF0E5A47),
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (onTap != null)
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF0E5A47),
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showCompactPaymentNotice(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        width: 168,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFF0E5A47),
      ),
    );
}

class SellerActiveOrderCard extends StatefulWidget {
  const SellerActiveOrderCard({
    super.key,
    required this.order,
    required this.onAction,
    required this.onOrderUpdated,
    required this.onPaymentConfirmed,
    required this.onReject,
    required this.onReadyBy,
    this.rejectBusy = false,
  });

  final Order order;
  final Future<void> Function(Order order, String nextStatus) onAction;
  final void Function(Order order) onOrderUpdated;
  final Future<void> Function() onPaymentConfirmed;
  final Future<void> Function(Order order) onReject;
  final Future<void> Function(Order order) onReadyBy;
  final bool rejectBusy;

  @override
  State<SellerActiveOrderCard> createState() => _SellerActiveOrderCardState();
}

class _SellerActiveOrderCardState extends State<SellerActiveOrderCard> {
  bool _isUpdating = false;
  bool _isConfirmingPayment = false;

  Future<void> _handleAction(String nextStatus) async {
    if (_isUpdating) return;
    final order = widget.order;
    if (nextStatus == 'accepted' &&
        order.requestedEarlierThanUsualLead &&
        order.requestedReadyAt != null) {
      final confirmed = await confirmEarlierThanUsualLead(
        context,
        requestedReadyAt: order.requestedReadyAt!,
        usualLeadLabel: order.usualLeadTimeLabel.isEmpty
            ? 'your usual preparation time'
            : order.usualLeadTimeLabel,
      );
      if (!confirmed) return;
    }
    setState(() => _isUpdating = true);
    try {
      await widget.onAction(order, nextStatus);
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _confirmPayment() async {
    final result = await showModalBottomSheet<Object?>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _ReadyBySheet(
        orderId: widget.order.orderId,
        allowClear: false,
        initial: widget.order.expectedReadyAt,
      ),
    );
    if (!mounted || result == null) return;

    setState(() => _isConfirmingPayment = true);
    try {
      DateTime? expectedReadyAt;
      num? readyInMinutes;
      if (result is DateTime) {
        expectedReadyAt = result;
      } else if (result is num) {
        readyInMinutes = result;
      }
      final json = await ApiService.confirmPayment(
        orderId: widget.order.id,
        expectedReadyAt: expectedReadyAt,
        readyInMinutes: readyInMinutes,
      );
      widget.onOrderUpdated(Order.fromJson(json));
      await widget.onPaymentConfirmed();
      if (!mounted) return;
      _showCompactPaymentNotice(context, 'Payment confirmed');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not confirm payment: $e')));
    } finally {
      if (mounted) setState(() => _isConfirmingPayment = false);
    }
  }

  Future<void> _confirmCashPayment() async {
    final order = widget.order;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm cash received?'),
        content: Text(
          'Confirm that you have received ₹${order.total.toStringAsFixed(0)} in cash?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF0E5A47),
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isConfirmingPayment = true);
    try {
      final json = await ApiService.confirmCashPayment(orderId: order.id);
      widget.onOrderUpdated(Order.fromJson(json));
      await widget.onPaymentConfirmed();
      if (!mounted) return;
      _showCompactPaymentNotice(context, 'Payment received');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not confirm cash payment: $e')),
      );
    } finally {
      if (mounted) setState(() => _isConfirmingPayment = false);
    }
  }

  Future<void> _completeOrder() async {
    if (_isUpdating) return;
    final confirmed = await confirmCompleteOrder(context);
    if (!confirmed || !mounted) return;

    setState(() => _isUpdating = true);
    try {
      await widget.onAction(widget.order, 'completed');
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final lifecycle = SellerOrderLifecycle.forStatus(order.status);
    final payment = SellerPaymentActions.fromOrder(
      status: order.status,
      paymentMethod: order.paymentMethod,
      paymentStatus: order.paymentStatus,
    );
    final isCash = payment.isCash;
    final cashPaid = order.paymentStatus == 'paid';
    final needsCashConfirm = isCash &&
        lifecycle.treatAsReady &&
        !cashPaid &&
        order.paymentStatus != 'failed';
    final canComplete = lifecycle.showComplete && (!isCash || cashPaid);
    final hasSellerAction =
        lifecycle.showAccept || payment.showMarkReady || canComplete;
    final rejectLocked = widget.rejectBusy || order.isRejected;
    final canReject = lifecycle.showReject || rejectLocked;
    final canSetReadyBy = payment.canSetReadyBy;
    final showUpiConfirm = payment.showConfirmOrderAndChooseTime;
    final showUpiPaymentPending = payment.showPaymentPending;

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
            children: [
              if (order.items.isNotEmpty) ...[
                ListingImage(
                  food: order.items.first.food,
                  width: 56,
                  height: 56,
                  borderRadius: 14,
                  iconSize: 26,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.items.length == 1
                          ? order.items.first.food.name
                          : order.itemsSummary,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101617),
                      ),
                    ),
                    if (order.items.length == 1) ...[
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
                      '${order.orderId} • ${order.placedAtLabel}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8A9491),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      order.buyerLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF3A4644),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (order.requestedReadyAt != null) ...[
                      const SizedBox(height: 8),
                      RequestedReadySummary(
                        order: order,
                        isSellerView: true,
                      ),
                    ],
                    if (order.fulfilmentMethod != null &&
                        order.fulfilmentMethod!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      OrderFulfilmentBanner(
                        order: order,
                        isSellerView: true,
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
                  color: Color(0xFF0E5A47),
                ),
              ),
            ],
          ),
          if (order.items.length > 1) ...[
            const SizedBox(height: 10),
            OrderItemsList(
              items: order.items,
              compact: true,
              showSellerName: false,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: lifecycle.treatAsReady || lifecycle.showMarkReady
                      ? const Color(0xFFE8F5EE)
                      : const Color(0xFFEDE8F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  lifecycle.badge,
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                    color: lifecycle.treatAsReady || lifecycle.showMarkReady
                        ? const Color(0xFF0E5A47)
                        : const Color(0xFF5A3E8A),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _PaymentBadge(paymentStatus: order.paymentStatus),
              if (isCash) ...[
                const SizedBox(width: 8),
                const Text(
                  'CASH',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF8A9491),
                  ),
                ),
              ],
              const Spacer(),
              const SizedBox(width: 8),
              OrderMessagesButton(
                order: order,
                isSellerView: true,
                inline: true,
                onClosed: widget.onPaymentConfirmed,
              ),
            ],
          ),
          if (lifecycle.headline != null) ...[
            const SizedBox(height: 12),
            Text(
              lifecycle.headline!,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: Color(0xFF101617),
              ),
            ),
            if (lifecycle.detail != null) ...[
              const SizedBox(height: 2),
              Text(
                lifecycle.detail!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6A7774),
                ),
              ),
            ],
          ],
          if (showUpiPaymentPending) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFE0A3)),
              ),
              child: Text(
                order.paymentStatus == 'buyer_marked_paid'
                    ? 'Payment Pending — buyer marked paid'
                    : 'Payment Pending',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFB8860B),
                ),
              ),
            ),
          ],
          if (showUpiConfirm) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton.icon(
                onPressed: _isConfirmingPayment ? null : _confirmPayment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE85D04),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                icon: _isConfirmingPayment
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_circle_rounded, size: 18),
                label: Text(
                  _isConfirmingPayment
                      ? 'Confirming...'
                      : 'Confirm Order & Choose Time',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
          if (needsCashConfirm) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F0),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD4D4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Payment',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF8A9491),
                      letterSpacing: 0.4,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Cash on Delivery',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFD94F4F),
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Payment Pending',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFFD94F4F),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: ElevatedButton.icon(
                      onPressed: _isConfirmingPayment
                          ? null
                          : _confirmCashPayment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE85D04),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      icon: _isConfirmingPayment
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.payments_rounded, size: 18),
                      label: Text(
                        _isConfirmingPayment
                            ? 'Confirming...'
                            : 'Confirm Payment Received',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (isCash && cashPaid && canComplete) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: Container(
                key: const Key('payment-received-banner'),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5EE),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFD4E8DF)),
                ),
                child: const Text(
                  'Payment received',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0E5A47),
                  ),
                ),
              ),
            ),
          ],
          if (hasSellerAction) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: ElevatedButton(
                onPressed: _isUpdating || rejectLocked
                    ? null
                    : () {
                        if (canComplete) {
                          _completeOrder();
                        } else if (lifecycle.showMarkReady) {
                          _handleAction('ready');
                        } else if (lifecycle.showAccept) {
                          _handleAction('accepted');
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0E5A47),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: const Color(0xFFE8EDEB),
                  disabledForegroundColor: const Color(0xFF6A7774),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isUpdating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        lifecycle.primaryLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
              ),
            ),
          ],
          if (canSetReadyBy) ...[
            const SizedBox(height: 8),
            if (order.showExpectedReadyAt) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F7F4),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFD4E8DF)),
                ),
                child: Text(
                  'Ready by ${Order.formatReadyBy(order.expectedReadyAt!)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0E5A47),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
            SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton.icon(
                onPressed: _isUpdating ? null : () => widget.onReadyBy(order),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF0E5A47),
                  side: const BorderSide(color: Color(0xFFD4E8DF)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.schedule_rounded, size: 18),
                label: Text(
                  order.expectedReadyAt == null
                      ? 'Set Ready by'
                      : 'Update Ready by',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
          if (canReject) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              height: 42,
              child: OutlinedButton.icon(
                key: const Key('seller-reject-button'),
                onPressed: rejectLocked || _isUpdating
                    ? null
                    : () => widget.onReject(order),
                style: OutlinedButton.styleFrom(
                  foregroundColor: rejectLocked
                      ? const Color(0xFF8A9491)
                      : const Color(0xFFD94F4F),
                  disabledForegroundColor: const Color(0xFF8A9491),
                  side: BorderSide(
                    color: rejectLocked
                        ? const Color(0xFFE0E5E3)
                        : const Color(0xFFFFD4D4),
                  ),
                  backgroundColor: rejectLocked
                      ? const Color(0xFFF0F2F1)
                      : Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text(
                  'Reject',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PaymentBadge extends StatelessWidget {
  const _PaymentBadge({required this.paymentStatus});

  final String paymentStatus;

  @override
  Widget build(BuildContext context) {
    String label;
    Color textColor;
    Color bgColor;

    switch (paymentStatus) {
      case 'seller_confirmed':
      case 'paid':
        label = 'PAID ✓';
        textColor = const Color(0xFF0E5A47);
        bgColor = const Color(0xFFE8F5EE);
        break;
      case 'buyer_marked_paid':
        label = 'BUYER PAID';
        textColor = const Color(0xFFB8860B);
        bgColor = const Color(0xFFFFF8E8);
        break;
      default:
        label = 'UNPAID';
        textColor = const Color(0xFFD94F4F);
        bgColor = const Color(0xFFFFF0F0);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          letterSpacing: 0.6,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }
}

class _OrdersSegment extends StatelessWidget {
  const _OrdersSegment({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.badgeCount = 0,
    this.badgeKey,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int badgeCount;
  final Key? badgeKey;

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
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: selected
                          ? Colors.white
                          : const Color(0xFF6A7774),
                    ),
                  ),
                ),
                if (badgeCount > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    key: badgeKey,
                    constraints: const BoxConstraints(minWidth: 18),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white
                          : const Color(0xFFE85D04),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badgeCount > 9 ? '9+' : '$badgeCount',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                        color: selected
                            ? const Color(0xFFE85D04)
                            : Colors.white,
                      ),
                    ),
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

class SellerPastOrderCard extends StatelessWidget {
  const SellerPastOrderCard({super.key, required this.order, this.onRefresh});

  final Order order;
  final Future<void> Function()? onRefresh;

  @override
  Widget build(BuildContext context) {
    final isCancelled = order.status == 'cancelled';
    final isRejected = order.status == 'rejected';
    final statusLabel = isRejected
        ? 'REJECTED'
        : isCancelled
        ? 'CANCELLED'
        : 'COMPLETED';
    final statusColor = isRejected || isCancelled
        ? const Color(0xFFD94F4F)
        : const Color(0xFF0E5A47);
    final statusBg = isRejected || isCancelled
        ? const Color(0xFFFFF0F0)
        : const Color(0xFFE8F5EE);

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
                  width: 56,
                  height: 56,
                  borderRadius: 14,
                  iconSize: 26,
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.items.length == 1
                          ? order.items.first.food.name
                          : order.itemsSummary,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101617),
                      ),
                    ),
                    if (order.items.length == 1) ...[
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
                      '${order.orderId} • ${order.placedAtLabel}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF8A9491),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      order.buyerLabel,
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF3A4644),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (order.requestedReadyAt != null) ...[
                      const SizedBox(height: 8),
                      RequestedReadySummary(
                        order: order,
                        isSellerView: true,
                      ),
                    ],
                    if (order.fulfilmentMethod != null &&
                        order.fulfilmentMethod!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      OrderFulfilmentBanner(
                        order: order,
                        isSellerView: true,
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
            const SizedBox(height: 10),
            OrderItemsList(
              items: order.items,
              compact: true,
              showSellerName: false,
            ),
          ],
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
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
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _PaymentBadge(paymentStatus: order.paymentStatus),
              const Spacer(),
              const SizedBox(width: 8),
              OrderMessagesButton(
                order: order,
                isSellerView: true,
                inline: true,
                onClosed: onRefresh,
              ),
            ],
          ),
          if (isRejected &&
              order.rejectReason != null &&
              order.rejectReason!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF5F5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFD4D4)),
              ),
              child: Text(
                'Reason: ${order.rejectReason}',
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF8A3030),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Returns: preset minutes | custom DateTime | 'skip' | 'clear' | null.
class _ReadyBySheet extends StatefulWidget {
  const _ReadyBySheet({
    required this.orderId,
    this.allowClear = false,
    this.initial,
  });

  final String orderId;
  final bool allowClear;
  final DateTime? initial;

  @override
  State<_ReadyBySheet> createState() => _ReadyBySheetState();
}

class _ReadyBySheetState extends State<_ReadyBySheet> {
  static const _presets = [
    (15, '15 min'),
    (30, '30 min'),
    (45, '45 min'),
    (60, '1 hour'),
  ];

  Future<void> _pickCustom() async {
    final now = DateTime.now();
    final currentEstimate = widget.initial?.toLocal();
    final initial = currentEstimate?.isAfter(now) == true
        ? currentEstimate!
        : now.add(const Duration(minutes: 30));
    final picked = await pickDateAndSimpleTime(
      context,
      initial: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 2)),
    );
    if (picked == null || !mounted) return;
    if (!picked.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ready by must be in the future')),
      );
      return;
    }
    Navigator.pop(context, picked);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ready by',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Optional estimate for ${widget.orderId}. You can skip this.',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6A7774),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets.map((p) {
              return ActionChip(
                label: Text(p.$2),
                onPressed: () {
                  Navigator.pop(context, p.$1);
                },
                backgroundColor: const Color(0xFFF0F7F4),
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0E5A47),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _pickCustom,
              icon: const Icon(Icons.schedule_rounded, size: 18),
              label: const Text('Choose time'),
            ),
          ),
          if (widget.allowClear) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.pop(context, 'clear'),
                child: const Text('Remove estimate'),
              ),
            ),
          ],
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context, 'skip'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0E5A47),
                foregroundColor: Colors.white,
              ),
              child: const Text('Skip'),
            ),
          ),
        ],
      ),
    );
  }
}
