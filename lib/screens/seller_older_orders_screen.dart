import 'package:flutter/material.dart';

import '../models/data.dart';
import '../models/seller_order_history.dart';
import '../services/api_service.dart';
import '../widgets/app_header.dart';
import 'seller_dashboard_screen.dart';

class SellerOlderOrdersScreen extends StatefulWidget {
  const SellerOlderOrdersScreen({
    super.key,
    this.fetchOrders,
    this.onOrderRefresh,
  });

  /// Same test seam as My Kitchen. Production uses the scoped Orders API.
  final Future<List<Map<String, dynamic>>> Function()? fetchOrders;
  final Future<void> Function()? onOrderRefresh;

  @override
  State<SellerOlderOrdersScreen> createState() =>
      _SellerOlderOrdersScreenState();
}

class _SellerOlderOrdersScreenState extends State<SellerOlderOrdersScreen> {
  static const _pageSize = 20;

  final List<Order> _orders = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({required bool reset}) async {
    if (_loadingMore) return;
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _page = 1;
        _orders.clear();
      });
    } else {
      if (!_hasMore) return;
      setState(() => _loadingMore = true);
    }

    try {
      final page = reset ? 1 : _page + 1;
      late final List<Order> next;
      late final bool hasMore;

      final injected = widget.fetchOrders;
      if (injected != null) {
        final parsed = (await injected()).map(Order.fromJson).toList();
        final older = parsed
            .where(
              (order) =>
                  order.isTerminal &&
                  !isSellerRecentPastOrder(
                    isTerminal: order.isTerminal,
                    completedAt: order.completedAt,
                    cancelledAt: order.cancelledAt,
                    rejectedAt: order.rejectedAt,
                    createdAt: order.createdAt,
                  ),
            )
            .toList();
        final start = (page - 1) * _pageSize;
        final end = start + _pageSize;
        next = start >= older.length
            ? const []
            : older.sublist(start, end > older.length ? older.length : end);
        hasMore = end < older.length;
      } else {
        final bucket = await ApiService.getSellerOrderBucket(
          scope: 'older',
          page: page,
          limit: _pageSize,
        );
        next = bucket.orders.map(Order.fromJson).toList();
        hasMore = bucket.hasMore;
      }

      if (!mounted) return;
      setState(() {
        _page = page;
        _hasMore = hasMore;
        _orders.addAll(next);
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              showCart: false,
              padding: const EdgeInsets.fromLTRB(4, 10, 20, 0),
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                color: const Color(0xFF3A4644),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Older Orders',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101617),
                  ),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFF0E5A47),
                onRefresh: () => _load(reset: true),
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          Center(child: Text('Loading older orders…')),
        ],
      );
    }
    if (_error != null && _orders.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error!, textAlign: TextAlign.center),
          ),
        ],
      );
    }
    if (_orders.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          Padding(
            padding: EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Text(
              'No older orders.\n\nCompleted and cancelled sales older than 7 days will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF3A4644),
                height: 1.45,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      );
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification.metrics.pixels >
            notification.metrics.maxScrollExtent - 240) {
          _load(reset: false);
        }
        return false;
      },
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
        itemCount: _orders.length + (_loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _orders.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return SellerPastOrderCard(
            order: _orders[index],
            onRefresh: widget.onOrderRefresh,
          );
        },
      ),
    );
  }
}
