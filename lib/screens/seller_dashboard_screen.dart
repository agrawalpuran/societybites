import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../widgets/order_items_list.dart';
import '../models/data.dart';
import '../services/api_service.dart';
import 'add_listing_screen.dart';
import 'my_listings_screen.dart';

class SellerDashboardScreen extends StatefulWidget {
  const SellerDashboardScreen({super.key});

  @override
  State<SellerDashboardScreen> createState() => _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends State<SellerDashboardScreen> {
  List<Order> _activeOrders = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadOrders();
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
        _activeOrders =
            parsed.where((o) => o.statusStep >= 0 && o.statusStep < 3).toList();
        _isLoading = false;
      });
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
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update order: $e')),
      );
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'preparing':
        return 'Preparing';
      case 'ready':
        return 'Ready for pickup';
      case 'completed':
        return 'Completed';
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
              SliverToBoxAdapter(child: _buildActiveOrders(context)),
              SliverToBoxAdapter(child: _buildExpandCard()),
              SliverToBoxAdapter(child: _buildAddListingCta(context)),
              const SliverToBoxAdapter(child: SizedBox(height: 30)),
            ],
          ),
        ),
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
          _OrdersStatCard(count: _activeOrders.length),
          const SizedBox(height: 12),
          Row(
            children: const [
              Expanded(child: _EarningsCard()),
              SizedBox(width: 12),
              Expanded(child: _SatisfactionCard()),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActiveOrders(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Text(
                'Active Orders',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101617),
                ),
              ),
              Spacer(),
              Text(
                'View History',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6A7774),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_activeOrders.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7F4),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFD4E8DF)),
              ),
              child: const Text(
                'No active orders yet.\n\n'
                'Seller mode uses the same login as buyer. Add a listing, '
                'then orders for your food will appear here.',
                style: TextStyle(
                  color: Color(0xFF3A4644),
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          else
            ..._activeOrders.map(
              (order) => _ActiveOrderCard(
                order: order,
                onAction: _updateStatus,
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
                onPressed: () {},
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
  const _OrdersStatCard({required this.count});

  final int count;

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
                  child: const Text(
                    '+20%',
                    style: TextStyle(
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
  const _EarningsCard();

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
          const Text(
            '₹1,200',
            style: TextStyle(
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
  const _SatisfactionCard();

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
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: const [
              Text(
                '4.9',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101617),
                ),
              ),
              Text(
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
        ],
      ),
    );
  }
}

class _ActiveOrderCard extends StatefulWidget {
  const _ActiveOrderCard({
    required this.order,
    required this.onAction,
  });

  final Order order;
  final Future<void> Function(Order order, String nextStatus) onAction;

  @override
  State<_ActiveOrderCard> createState() => _ActiveOrderCardState();
}

class _ActiveOrderCardState extends State<_ActiveOrderCard> {
  bool _isUpdating = false;

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

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isPrep = order.statusStep == 1;
    final isOrdered = order.statusStep == 0;
    final isReady = order.statusStep == 2;

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
                  color: isPrep
                      ? const Color(0xFFE8F5EE)
                      : const Color(0xFFEDE8F5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isPrep
                      ? 'IN PREP'
                      : isOrdered
                          ? 'RECEIVED'
                          : isReady
                              ? 'READY'
                              : 'ACTIVE',
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.6,
                    fontWeight: FontWeight.w700,
                    color: isPrep
                        ? const Color(0xFF0E5A47)
                        : const Color(0xFF5A3E8A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: ElevatedButton(
                    onPressed: _isUpdating || isReady
                        ? null
                        : () {
                            if (isPrep) {
                              _handleAction('ready');
                            } else if (isOrdered) {
                              _handleAction('preparing');
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0E5A47),
                      foregroundColor: Colors.white,
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
                                : isPrep
                                    ? 'Mark Ready'
                                    : 'Accept Order',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 13),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F7F6),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE0E5E3)),
                ),
                child: const Icon(Icons.phone_rounded,
                    size: 20, color: Color(0xFF3A4644)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
