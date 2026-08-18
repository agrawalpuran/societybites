import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../widgets/app_header.dart';
import '../widgets/order_items_list.dart';
import '../models/data.dart';
import '../services/api_service.dart';
import '../services/seller_onboarding.dart';
import 'add_listing_screen.dart';
import 'my_listings_screen.dart';
import 'seller_feedback_screen.dart';

class SellerDashboardScreen extends StatefulWidget {
  const SellerDashboardScreen({super.key});

  @override
  SellerDashboardScreenState createState() => SellerDashboardScreenState();
}

class SellerDashboardScreenState extends State<SellerDashboardScreen> {
  List<Order> _activeOrders = [];
  List<Order> _pastOrders = [];
  bool _isLoading = true;
  String? _error;
  Map<String, dynamic> _stats = {};
  /// 0 = Active, 1 = Past
  int _ordersTab = 0;

  @override
  void initState() {
    super.initState();
    _loadOrders();
    _loadStats();
  }

  /// Called by MainShell when Dashboard tab is selected or app resumes.
  void refresh() {
    _loadOrders();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final stats = await ApiService.getSellerStats();
      if (!mounted) return;
      setState(() => _stats = stats);
    } catch (_) {}
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final orders = await ApiService.getOrders(role: 'seller');
      final parsed = orders.map(Order.fromJson).toList();

      if (!mounted) return;

      setState(() {
        _activeOrders = parsed.where((o) => !o.isTerminal).toList();
        _pastOrders = parsed.where((o) => o.isTerminal).toList();
        _isLoading = false;
      });
      _loadStats();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _updateStatus(Order order, String nextStatus) async {
    try {
      await ApiService.updateOrderStatus(
        orderId: order.id,
        status: nextStatus,
      );
      await _loadOrders();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Order updated to ${_statusLabel(nextStatus)}'),
          backgroundColor: const Color(0xFF0E5A47),
        ),
      );

      // Optional Ready-by: never blocks accept; Skip leaves NULL.
      if (nextStatus == 'accepted') {
        await _promptReadyBy(order.id, order.orderId);
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update order: $e')),
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
      builder: (ctx) => _ReadyBySheet(
        orderId: orderNumber,
        allowClear: false,
      ),
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
        await ApiService.setOrderReadyTime(orderId: orderId, expectedReadyAt: null);
      } else if (result is DateTime) {
        await ApiService.setOrderReadyTime(
          orderId: orderId,
          expectedReadyAt: result,
        );
      } else {
        return;
      }
      await _loadOrders();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result == 'clear' ? 'Ready by estimate removed' : 'Ready by updated',
          ),
          backgroundColor: const Color(0xFF0E5A47),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update Ready by: $e')),
      );
    }
  }

  Future<void> _rejectOrder(Order order) async {
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _RejectOrderSheet(orderId: order.orderId),
    );

    if (result == null || !mounted) return;

    try {
      await ApiService.rejectOrder(
        orderId: order.id,
        reason: result['reason']!,
        otherText: result['otherText'],
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not reject order: $e')),
      );
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pending';
      case 'accepted':
        return 'Accepted';
      case 'preparing':
        return 'Preparing';
      case 'ready':
        return 'Ready for pickup';
      case 'picked_up':
        return 'Picked up';
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
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAF9),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF0E5A47),
          onRefresh: _loadOrders,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader(context)),
              SliverToBoxAdapter(child: _buildStatsGrid()),
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
              SliverToBoxAdapter(child: _buildOrdersSection(context)),
              SliverToBoxAdapter(child: _buildExpandCard()),
              SliverToBoxAdapter(child: _buildAddListingCta(context)),
              const SliverToBoxAdapter(child: SizedBox(height: 30)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOrdersSection(BuildContext context) {
    final showingPast = _ordersTab == 1;
    final orders = showingPast ? _pastOrders : _activeOrders;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Orders',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Active sales and completed history for your kitchen.',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF6A7774),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
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
            ...orders.map((order) => _SellerPastOrderCard(order: order))
          else
            ...orders.map(
              (order) => _ActiveOrderCard(
                order: order,
                onAction: _updateStatus,
                onPaymentConfirmed: _loadOrders,
                onReject: _rejectOrder,
                onReadyBy: _editReadyBy,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppHeader(),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFFFE5D6),
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Text(
            'SELLER OVERVIEW',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.3,
              fontWeight: FontWeight.w700,
              color: Color(0xFF4E2A20),
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Good morning,\nChef.',
          style: TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.w800,
            color: Color(0xFF101617),
            height: 1.15,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          "Your community kitchen is buzzing.\nHere's what's happening in your\nneighborhood today.",
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF6A7774),
            fontWeight: FontWeight.w500,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  Widget _buildStatsGrid() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        children: [
          _OrdersStatCard(
            count: _activeOrders.length,
            activeListings: (_stats['activeListings'] as num?)?.toInt(),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _EarningsCard(
                  amount: (_stats['todayRevenue'] as num?)?.toDouble() ?? 0,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
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
              ),
            ],
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
                    const SnackBar(content: Text('This feature is coming soon')),
                  );
                },
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF0E5A47), width: 1.5),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
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
                  MaterialPageRoute(
                    builder: (_) => const MyListingsScreen(),
                  ),
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
                final canList =
                    await SellerOnboarding.ensureCanCreateListing(context);
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

class _OrdersStatCard extends StatelessWidget {
  const _OrdersStatCard({required this.count, this.activeListings});

  final int count;
  final int? activeListings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F7F4),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.shopping_bag_rounded,
                      color: Color(0xFF0E5A47), size: 20),
                ),
                const SizedBox(height: 14),
                Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101617),
                  ),
                ),
                const Text(
                  'Orders Today',
                  style: TextStyle(
                    fontSize: 14,
                    color: Color(0xFF6A7774),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFF0F7F4),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.restaurant_rounded,
                    color: const Color(0xFF0E5A47).withAlpha(120), size: 28),
                const SizedBox(height: 4),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F0EA),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    activeListings != null
                        ? '$activeListings listed'
                        : '0 listed',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0E5A47),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EarningsCard extends StatelessWidget {
  const _EarningsCard({this.amount = 0});

  final double amount;

  @override
  Widget build(BuildContext context) {
    return Container(
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
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F7F4),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: const Icon(Icons.play_circle_fill_rounded,
                    color: Color(0xFF0E5A47), size: 18),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF0E5A47),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  'DAILY GOAL',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 0.8,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '₹${amount.toStringAsFixed(0)}',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
          const Text(
            'Earnings',
            style: TextStyle(
              fontSize: 13,
              color: Color(0xFF6A7774),
              fontWeight: FontWeight.w600,
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
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFEAEFED)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF8E8),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.star_rounded,
                        color: Colors.amber, size: 18),
                  ),
                  const Spacer(),
                  if (onTap != null)
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFFADB5B2),
                      size: 20,
                    ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    rating > 0 ? rating.toString() : '—',
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF101617),
                    ),
                  ),
                  const Text(
                    '/5',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8A9491),
                    ),
                  ),
                ],
              ),
              const Text(
                'Satisfaction Score',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6A7774),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                'View feedback',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF0E5A47),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActiveOrderCard extends StatefulWidget {
  const _ActiveOrderCard({
    required this.order,
    required this.onAction,
    required this.onPaymentConfirmed,
    required this.onReject,
    required this.onReadyBy,
  });

  final Order order;
  final Future<void> Function(Order order, String nextStatus) onAction;
  final Future<void> Function() onPaymentConfirmed;
  final Future<void> Function(Order order) onReject;
  final Future<void> Function(Order order) onReadyBy;

  @override
  State<_ActiveOrderCard> createState() => _ActiveOrderCardState();
}

class _ActiveOrderCardState extends State<_ActiveOrderCard> {
  bool _isUpdating = false;
  bool _isConfirmingPayment = false;

  Future<void> _handleAction(String nextStatus) async {
    setState(() => _isUpdating = true);
    try {
      await widget.onAction(widget.order, nextStatus);
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }

  Future<void> _confirmPayment() async {
    setState(() => _isConfirmingPayment = true);
    try {
      // Confirm already moves the order to preparing + seller_confirmed.
      await ApiService.confirmPayment(orderId: widget.order.id);
      await widget.onPaymentConfirmed();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment confirmed — order is now preparing'),
          backgroundColor: Color(0xFF0E5A47),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not confirm payment: $e')),
      );
    } finally {
      if (mounted) setState(() => _isConfirmingPayment = false);
    }
  }

  Future<void> _callBuyer() async {
    final phone = widget.order.buyerPhone?.trim();
    if (phone == null || phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Buyer phone is not available')),
      );
      return;
    }
    final uri = Uri(scheme: 'tel', path: phone);
    try {
      final launched = await launchUrl(uri);
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not dial $phone')),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not dial $phone')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isPending = order.status == 'pending';
    final isAccepted = order.status == 'accepted';
    final isPrep = order.status == 'preparing';
    final isReady = order.status == 'ready';
    final isPickedUp = order.status == 'picked_up';
    final hasSellerAction = isPending || isAccepted || isPrep;
    final canReject = isPending || isAccepted || isPrep;
    final canSetReadyBy = isAccepted || isPrep;

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: isPrep || isPickedUp
                      ? const Color(0xFFE8F5EE)
                      : const Color(0xFFEDE8F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isPrep
                      ? 'IN PREP'
                      : isPending
                          ? 'NEW'
                          : isAccepted
                              ? 'ACCEPTED'
                              : isReady
                                  ? 'READY'
                                  : isPickedUp
                                      ? 'PICKED UP'
                                      : 'ACTIVE',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                    color: isPrep || isPickedUp
                        ? const Color(0xFF0E5A47)
                        : const Color(0xFF5A3E8A),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _PaymentBadge(paymentStatus: order.paymentStatus),
            ],
          ),
          if (order.paymentStatus == 'buyer_marked_paid') ...[
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
                      borderRadius: BorderRadius.circular(12)),
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
                  _isConfirmingPayment ? 'Confirming...' : 'Confirm Payment',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton(
                    onPressed: _isUpdating || !hasSellerAction
                        ? null
                        : () {
                            if (isPrep) {
                              _handleAction('ready');
                            } else if (isAccepted) {
                              _handleAction('preparing');
                            } else if (isPending) {
                              _handleAction('accepted');
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0E5A47),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFE8EDEB),
                      disabledForegroundColor: const Color(0xFF6A7774),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
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
                            isReady
                                ? 'Awaiting pickup'
                                : isPickedUp
                                    ? 'Waiting for buyer to complete'
                                    : isPrep
                                        ? 'Mark Ready'
                                        : isAccepted
                                            ? 'Start Preparing'
                                            : 'Accept Order',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: const Color(0xFFF5F7F6),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: _callBuyer,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE0E5E3)),
                    ),
                    child: const Icon(Icons.phone_rounded,
                        size: 20, color: Color(0xFF3A4644)),
                  ),
                ),
              ),
            ],
          ),
          if (canSetReadyBy) ...[
            const SizedBox(height: 8),
            if (order.showExpectedReadyAt) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
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
                onPressed: _isUpdating
                    ? null
                    : () => widget.onReject(order),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFD94F4F),
                  side: const BorderSide(color: Color(0xFFFFD4D4)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.cancel_outlined, size: 18),
                label: const Text(
                  'Reject Order',
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
  const _SellerPastOrderCard({required this.order});

  final Order order;

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
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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

class _RejectOrderSheet extends StatefulWidget {
  const _RejectOrderSheet({required this.orderId});

  final String orderId;

  @override
  State<_RejectOrderSheet> createState() => _RejectOrderSheetState();
}

class _RejectOrderSheetState extends State<_RejectOrderSheet> {
  static const _reasons = [
    'Food sold out',
    'Unable to prepare today',
    'Kitchen closed',
    'Ingredients unavailable',
    'Other',
  ];

  String? _selected;
  final _otherController = TextEditingController();

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  bool get _canSubmit {
    if (_selected == null) return false;
    if (_selected == 'Other') {
      final text = _otherController.text.trim();
      return text.isNotEmpty && text.length <= 200;
    }
    return true;
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
            'Reject Order',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose a reason for rejecting ${widget.orderId}. Inventory will be restored.',
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF6A7774),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          ..._reasons.map((reason) {
            final selected = _selected == reason;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Material(
                color: selected
                    ? const Color(0xFFFFF0F0)
                    : const Color(0xFFF5F7F6),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => setState(() => _selected = reason),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          selected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 20,
                          color: selected
                              ? const Color(0xFFD94F4F)
                              : const Color(0xFF8A9491),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          reason,
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: selected
                                ? const Color(0xFF8A3030)
                                : const Color(0xFF3A4644),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          if (_selected == 'Other') ...[
            const SizedBox(height: 4),
            TextField(
              controller: _otherController,
              maxLength: 200,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Describe the reason…',
                filled: true,
                fillColor: const Color(0xFFF5F7F6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: !_canSubmit
                      ? null
                      : () {
                          Navigator.pop(context, {
                            'reason': _selected!,
                            if (_selected == 'Other')
                              'otherText': _otherController.text.trim(),
                          });
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD94F4F),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFE8EDEB),
                  ),
                  child: const Text('Confirm Reject'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Returns: DateTime | 'skip' | 'clear' | null (dismissed).
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
    final initial = widget.initial?.isAfter(now) == true
        ? widget.initial!
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

    final picked =
        DateTime(date.year, date.month, date.day, time.hour, time.minute);
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
                  Navigator.pop(
                    context,
                    DateTime.now().add(Duration(minutes: p.$1)),
                  );
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
