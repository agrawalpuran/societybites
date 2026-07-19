import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import '../widgets/order_items_list.dart';
import '../models/data.dart';
import '../services/api_service.dart';
import 'feedback_screen.dart';
import 'food_detail_screen.dart';
import 'payment_screen.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key, this.onExploreHome});

  /// Switches to the home tab in the main shell (e.g. "Explore" CTA).
  final VoidCallback? onExploreHome;

  @override
  OrdersScreenState createState() => OrdersScreenState();
}

class OrdersScreenState extends State<OrdersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Order> _activeOrders = [];
  List<Order> _pastOrders = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadOrders();
  }

  void refresh() => _loadOrders();

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final orders = await ApiService.getOrders(role: 'buyer');
      final parsed = orders.map(Order.fromJson).toList();

      if (!mounted) return;

      setState(() {
        _activeOrders =
            parsed.where((o) => o.status != 'completed' && o.status != 'cancelled').toList();
        _pastOrders = parsed.where((o) => o.status == 'completed' || o.status == 'cancelled').toList();
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
            const SizedBox(height: 18),
            _buildTabs(),
            const SizedBox(height: 16),
            if (_isLoading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
                ),
              )
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      _error!,
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
                    _ActiveTab(orders: _activeOrders, onRefresh: _loadOrders),
                    _PastTab(
                      orders: _pastOrders,
                      onRefresh: _loadOrders,
                      onExploreHome: widget.onExploreHome,
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
          labelStyle:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          tabs: const [Tab(text: 'Active'), Tab(text: 'Past')],
        ),
      ),
    );
  }
}

class _ActiveTab extends StatelessWidget {
  const _ActiveTab({required this.orders, required this.onRefresh});

  final List<Order> orders;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return const Center(child: Text('No active orders.'));
    }
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: orders
          .map((o) => _ActiveOrderCard(order: o, onRefresh: onRefresh))
          .toList(),
    );
  }
}

class _ActiveOrderCard extends StatelessWidget {
  const _ActiveOrderCard({required this.order, required this.onRefresh});

  final Order order;
  final Future<void> Function() onRefresh;

  static const _steps = ['Pending', 'Accepted', 'Preparing', 'Ready', 'Picked Up', 'Done'];

  String get _paymentLabel {
    switch (order.paymentStatus) {
      case 'buyer_marked_paid':
        return 'Awaiting Seller Confirmation';
      case 'seller_confirmed':
        return 'Payment Confirmed ✓';
      default:
        return 'Payment Pending';
    }
  }

  Color get _paymentColor {
    switch (order.paymentStatus) {
      case 'seller_confirmed':
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
              const Text(
                'ONGOING ORDER',
                style: TextStyle(
                  fontSize: 11,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8A9491),
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
          const SizedBox(height: 14),
          OrderItemsList(items: order.items),
          const SizedBox(height: 12),
          OrderTotalRow(order: order),
          const SizedBox(height: 20),
          _StatusTracker(currentStep: order.statusStep, steps: _steps),
          const SizedBox(height: 18),
          if (order.status == 'accepted' && order.paymentStatus == 'pending') ...[
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
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                icon: const Icon(Icons.payment_rounded, size: 18),
                label: const Text('Pay Now',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('This feature is coming soon')),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0E5A47),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              icon: const Icon(Icons.chat_bubble_rounded, size: 18),
              label: const Text('Message Seller',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(height: 10),
          if (order.status == 'ready') ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: () async {
                  try {
                    await ApiService.updateOrderStatus(
                      orderId: order.id,
                      status: 'picked_up',
                    );
                    await onRefresh();
                  } catch (e) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not complete order: $e')),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0E5A47),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                ),
                child: const Text(
                  'Mark Picked Up',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('This feature is coming soon')),
                );
              },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFD4DBD8)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.receipt_long_rounded,
                  size: 18, color: Color(0xFF3A4644)),
              label: const Text(
                'View Instructions',
                style: TextStyle(
                    fontWeight: FontWeight.w700, color: Color(0xFF3A4644)),
              ),
            ),
          ),
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
                      isCurrent ? Icons.restaurant_rounded : Icons.check_rounded,
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
  });

  final List<Order> orders;
  final Future<void> Function() onRefresh;
  final VoidCallback? onExploreHome;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 12),
          child: Text(
            'Past Orders',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
        ),
        ...orders.map((o) => _PastOrderTile(order: o, onRefresh: onRefresh)),
        const SizedBox(height: 20),
        _ExploreBanner(onExploreHome: onExploreHome),
      ],
    );
  }
}

class _PastOrderTile extends StatelessWidget {
  const _PastOrderTile({required this.order, required this.onRefresh});

  final Order order;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
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
                      '${order.sellerLabel} • ${order.date}',
                      style: const TextStyle(
                        fontSize: 13,
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
                  color: Color(0xFF101617),
                ),
              ),
            ],
          ),
          if (order.items.length > 1) ...[
            const SizedBox(height: 12),
            OrderItemsList(items: order.items, compact: true),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
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
                      horizontal: 12, vertical: 7),
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
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FoodDetailScreen(food: order.food),
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 7),
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
            ],
          ),
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
                    borderRadius: BorderRadius.circular(14)),
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
