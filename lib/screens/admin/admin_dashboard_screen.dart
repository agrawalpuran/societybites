import 'package:flutter/material.dart';

import '../../services/api_service.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Map<String, dynamic>? _stats;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getAdminDashboard();
      if (!mounted) return;
      setState(() {
        _stats = data;
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
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF6A7774)),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadStats,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0E5A47),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final stats = _stats!;

    return RefreshIndicator(
      color: const Color(0xFF0E5A47),
      onRefresh: _loadStats,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Platform Overview',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Color(0xFF101617),
              ),
            ),
            const SizedBox(height: 20),
            _SectionTitle(title: 'USERS'),
            const SizedBox(height: 10),
            _StatsGrid(cards: [
              _StatCard(
                label: 'Total Users',
                value: '${stats['totalUsers'] ?? 0}',
                icon: Icons.people_rounded,
              ),
              _StatCard(
                label: 'Sellers',
                value: '${stats['totalSellers'] ?? 0}',
                icon: Icons.storefront_rounded,
              ),
              _StatCard(
                label: 'Buyers',
                value: '${stats['totalBuyers'] ?? 0}',
                icon: Icons.person_rounded,
              ),
            ]),
            const SizedBox(height: 24),
            _SectionTitle(title: 'SOCIETIES & LISTINGS'),
            const SizedBox(height: 10),
            _StatsGrid(cards: [
              _StatCard(
                label: 'Societies',
                value: '${stats['totalSocieties'] ?? 0}',
                icon: Icons.apartment_rounded,
              ),
              _StatCard(
                label: 'Active Listings',
                value: '${stats['activeListings'] ?? 0}',
                icon: Icons.fastfood_rounded,
                color: const Color(0xFF2E7D32),
              ),
              _StatCard(
                label: 'Sold Out',
                value: '${stats['soldOutListings'] ?? 0}',
                icon: Icons.remove_shopping_cart_rounded,
                color: const Color(0xFFE65100),
              ),
            ]),
            const SizedBox(height: 24),
            _SectionTitle(title: 'ORDERS'),
            const SizedBox(height: 10),
            _StatsGrid(cards: [
              _StatCard(
                label: 'Total Orders',
                value: '${stats['totalOrders'] ?? 0}',
                icon: Icons.shopping_bag_rounded,
              ),
              _StatCard(
                label: 'Today',
                value: '${stats['ordersToday'] ?? 0}',
                icon: Icons.today_rounded,
                color: const Color(0xFF1565C0),
              ),
              _StatCard(
                label: 'Pending',
                value: '${stats['pendingOrders'] ?? 0}',
                icon: Icons.hourglass_bottom_rounded,
                color: const Color(0xFFF57C00),
              ),
              _StatCard(
                label: 'Completed',
                value: '${stats['completedOrders'] ?? 0}',
                icon: Icons.check_circle_rounded,
                color: const Color(0xFF2E7D32),
              ),
              _StatCard(
                label: 'Cancelled',
                value: '${stats['cancelledOrders'] ?? 0}',
                icon: Icons.cancel_rounded,
                color: const Color(0xFFC62828),
              ),
            ]),
            const SizedBox(height: 24),
            _SectionTitle(title: 'REVIEWS'),
            const SizedBox(height: 10),
            _StatsGrid(cards: [
              _StatCard(
                label: 'Total Reviews',
                value: '${stats['totalReviews'] ?? 0}',
                icon: Icons.star_rounded,
                color: const Color(0xFFF9A825),
              ),
              _StatCard(
                label: 'Avg Rating',
                value: (stats['avgRating'] as num?)?.toStringAsFixed(1) ?? '—',
                icon: Icons.trending_up_rounded,
                color: const Color(0xFFF9A825),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w700,
        color: Color(0xFF8A9491),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.cards});
  final List<_StatCard> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards.map((card) {
            final width =
                (constraints.maxWidth - (crossAxisCount - 1) * 12) /
                    crossAxisCount;
            return SizedBox(width: width, child: card);
          }).toList(),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.color = const Color(0xFF0E5A47),
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6A7774),
            ),
          ),
        ],
      ),
    );
  }
}
