import 'dart:async';

import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../widgets/listing_image.dart';
import '../widgets/order_items_list.dart';
import '../widgets/order_fulfilment_banner.dart';
import '../models/data.dart';
import '../models/order_lifecycle.dart';
import '../services/api_service.dart';
import '../widgets/order_lifecycle_dialogs.dart';
import '../services/seller_onboarding.dart';
import '../services/session_service.dart';
import '../widgets/preorder_widgets.dart';
import '../widgets/order_messages_button.dart';
import '../widgets/seller_insights_panel.dart';
import 'add_listing_screen.dart';
import 'my_listings_screen.dart';
import 'preorder_detail_screen.dart';
import 'seller_preorders_screen.dart';
import 'seller_feedback_screen.dart';

class SellerDashboardScreen extends StatefulWidget {
  const SellerDashboardScreen({super.key, this.onInitialLoadSettled});

  /// Fired once when the first orders load finishes (success or failure).
  final VoidCallback? onInitialLoadSettled;

  @override
  SellerDashboardScreenState createState() => SellerDashboardScreenState();
}

class SellerDashboardScreenState extends State<SellerDashboardScreen> {
  List<Order> _activeOrders = [];
  List<Order> _pastOrders = [];
  bool _isLoading = true;
  bool _hasSuccessfullyLoaded = false;
  String? _error;
  Map<String, dynamic> _stats = {};
  List<PreOrderCampaign> _preOrderCampaigns = [];
  bool _preOrdersLoading = true;
  bool _didNotifyInitialSettle = false;
  int _ordersLoadGen = 0;
  bool _ordersRefreshInFlight = false;

  /// 0 = Orders, 1 = Dashboard. Dashboard is the default seller landing tab.
  int _areaTab = 1;

  /// 0 = Active, 1 = Past
  int _ordersTab = 0;

  @override
  void initState() {
    super.initState();
    _loadOrders();
    _loadStats();
    _loadPreOrders();
  }

  bool get isLoadInProgress => _isLoading || _ordersRefreshInFlight;
  bool get hasSuccessfullyLoaded => _hasSuccessfullyLoaded;

  /// Called by MainShell on failed first-load retry, app resume, and FCM.
  void refresh() {
    _loadOrders();
    _loadStats();
    _loadPreOrders();
  }

  Future<void> _loadPreOrders() async {
    try {
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
      final raw = await ApiService.getPreOrderCampaigns(
        societyId: societyId,
        sellerId: sellerId,
      );
      final campaigns = await Future.wait(
        raw.map((json) async {
          final campaign = PreOrderCampaign.fromJson(json);
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
      campaigns.removeWhere(
        (campaign) => campaignDisplayStatus(campaign) == 'cancelled',
      );
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
      final orders = await ApiService.getOrders(role: 'seller');
      final parsed = orders.map(Order.fromJson).toList();

      if (!mounted || gen != _ordersLoadGen) return;

      setState(() {
        _activeOrders = parsed.where((o) => !o.isTerminal).toList();
        _pastOrders = parsed.where((o) => o.isTerminal).toList();
        _isLoading = false;
        _hasSuccessfullyLoaded = true;
        _ordersRefreshInFlight = false;
      });
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

  Future<void> _rejectOrder(Order order) async {
    if (_isRejecting) return;
    final confirmed = await confirmRejectOrder(context);
    if (!confirmed || !mounted) return;

    _isRejecting = true;
    try {
      await ApiService.rejectOrder(orderId: order.id);
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
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 48),
                              child: Center(
                                child: CircularProgressIndicator(
                                  color: Color(0xFF0E5A47),
                                ),
                              ),
                            ),
                          )
                        else
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
        ),
      ),
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
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 0),
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
          const SizedBox(height: 12),
          if (_preOrdersLoading)
            const SizedBox(
              height: 76,
              child: Center(
                child: CircularProgressIndicator(
                  color: preorderGreen,
                  strokeWidth: 2,
                ),
              ),
            )
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
    final orders = showingPast ? _pastOrders : _activeOrders;

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
                    label: 'Active (${_activeOrders.length})',
                    selected: !showingPast,
                    onTap: () => setState(() => _ordersTab = 0),
                  ),
                ),
                Expanded(
                  child: _OrdersSegment(
                    label: 'Past (${_pastOrders.length})',
                    selected: showingPast,
                    onTap: () => setState(() => _ordersTab = 1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (orders.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7F4),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFD4E8DF)),
              ),
              child: Text(
                showingPast
                    ? 'No past orders yet.\n\n'
                          'Completed and cancelled sales will appear here.'
                    : 'No active orders yet.\n\n'
                          'When neighbors order your food, they show up here.',
                style: const TextStyle(
                  color: Color(0xFF3A4644),
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else if (showingPast)
            ...orders.map(
              (order) => _SellerPastOrderCard(
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
              ),
            ),
        ],
      ),
    );
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

  Widget _buildAddListingCta(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 52,
            child: OutlinedButton.icon(
              onPressed: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyListingsScreen()),
                );
                _loadOrders();
              },
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
              onPressed: () async {
                final canList = await SellerOnboarding.ensureCanCreateListing(
                  context,
                );
                if (!canList || !context.mounted) return;

                final created = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(builder: (_) => const AddListingScreen()),
                );
                if (created == true) {
                  _loadOrders();
                }
              },
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

class SellerActiveOrderCard extends StatefulWidget {
  const SellerActiveOrderCard({
    super.key,
    required this.order,
    required this.onAction,
    required this.onOrderUpdated,
    required this.onPaymentConfirmed,
    required this.onReject,
    required this.onReadyBy,
  });

  final Order order;
  final Future<void> Function(Order order, String nextStatus) onAction;
  final void Function(Order order) onOrderUpdated;
  final Future<void> Function() onPaymentConfirmed;
  final Future<void> Function(Order order) onReject;
  final Future<void> Function(Order order) onReadyBy;

  @override
  State<SellerActiveOrderCard> createState() => _SellerActiveOrderCardState();
}

class _SellerActiveOrderCardState extends State<SellerActiveOrderCard> {
  bool _isUpdating = false;
  bool _isConfirmingPayment = false;

  Future<void> _handleAction(String nextStatus) async {
    if (_isUpdating) return;
    final order = widget.order;
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment confirmed'),
          backgroundColor: Color(0xFF0E5A47),
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment received'),
          backgroundColor: Color(0xFF0E5A47),
        ),
      );
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
    final canReject = lifecycle.showReject;
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
                      order.itemsSummary,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101617),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${order.orderId} • ${order.date}',
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
            OrderItemsList(items: order.items, compact: true),
          ],
          const SizedBox(height: 12),
          Row(
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
            ],
          ),
          const SizedBox(height: 12),
          OrderMessagesButton(
            order: order,
            isSellerView: true,
            onClosed: widget.onPaymentConfirmed,
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFE8F5EE),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD4E8DF)),
              ),
              child: const Text(
                'Payment Received',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0E5A47),
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
                onPressed: _isUpdating
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
                onPressed: _isUpdating ? null : () => widget.onReject(order),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD94F4F),
                  side: const BorderSide(color: Color(0xFFFFD4D4)),
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
                fontSize: 13,
                color: selected ? Colors.white : const Color(0xFF6A7774),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SellerPastOrderCard extends StatelessWidget {
  const _SellerPastOrderCard({required this.order, this.onRefresh});

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
                      order.itemsSummary,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101617),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${order.orderId} • ${order.date}',
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
            OrderItemsList(items: order.items, compact: true),
          ],
          const SizedBox(height: 12),
          Row(
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
              Text(
                (order.paymentMethod ?? 'upi').toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8A9491),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          OrderMessagesButton(
            order: order,
            isSellerView: true,
            onClosed: onRefresh,
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
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 2)),
    );
    if (date == null || !mounted) return;

    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;

    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
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
