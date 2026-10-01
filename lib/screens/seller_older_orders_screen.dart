import 'package:flutter/material.dart';

import '../web/web_page_frame.dart';

import '../models/data.dart';
import '../models/seller_order_history.dart';
import '../services/api_service.dart';
import '../widgets/app_header.dart';
import '../widgets/screen_loading_note.dart';
import '../widgets/status_banner.dart';
import 'seller_dashboard_screen.dart';

class SellerOlderOrdersScreen extends StatefulWidget {
  const SellerOlderOrdersScreen({
    super.key,
    this.openOrders = false,
    this.fetchOrders,
    this.onOrderRefresh,
    this.onAction,
    this.onOrderUpdated,
    this.onPaymentConfirmed,
    this.onReject,
    this.onReadyBy,
  });

  /// Incomplete orders still in progress vs finished Past orders.
  final bool openOrders;

  /// Same test seam as My Kitchen. Production uses the scoped Orders API.
  final Future<List<Map<String, dynamic>>> Function()? fetchOrders;
  final Future<void> Function()? onOrderRefresh;
  final Future<void> Function(Order order, String nextStatus)? onAction;
  final void Function(Order order)? onOrderUpdated;
  final Future<void> Function()? onPaymentConfirmed;
  final Future<void> Function(Order order)? onReject;
  final Future<void> Function(Order order)? onReadyBy;

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
  String? _rejectingOrderId;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  bool _isOlderOpen(Order order) =>
      !order.isTerminal &&
      !isSellerRecentOpenOrder(
        isTerminal: order.isTerminal,
        createdAt: order.createdAt,
      );

  bool _isOlderPast(Order order) => isSellerOlderPastOrder(
        isTerminal: order.isTerminal,
        completedAt: order.completedAt,
        cancelledAt: order.cancelledAt,
        rejectedAt: order.rejectedAt,
        createdAt: order.createdAt,
      );

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
            .where(widget.openOrders ? _isOlderOpen : _isOlderPast)
            .toList();
        final start = (page - 1) * _pageSize;
        final end = start + _pageSize;
        next = start >= older.length
            ? const []
            : older.sublist(start, end > older.length ? older.length : end);
        hasMore = end < older.length;
      } else {
        final bucket = await ApiService.getSellerOrderBucket(
          scope: widget.openOrders ? 'older_active' : 'older',
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

  Future<void> _reject(Order order) async {
    final reject = widget.onReject;
    if (reject == null) return;
    setState(() => _rejectingOrderId = order.id);
    try {
      await reject(order);
      if (mounted) await _load(reset: true);
    } finally {
      if (mounted) setState(() => _rejectingOrderId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return centerOnWeb(
      context,
      Scaffold(
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Older Orders',
                  style: const TextStyle(
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
    ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          ScreenLoadingNote(message: 'Loading older orders…'),
        ],
      );
    }
    if (_error != null && _orders.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          StatusBanner(message: _error!),
        ],
      );
    }
    if (_orders.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          StatusBanner(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            message: widget.openOrders
                ? 'No older open orders. Orders still in progress from more than 7 days ago will appear here.'
                : 'No older orders. Completed and cancelled sales older than 7 days will appear here.',
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
            return const ScreenLoadingNote(message: 'Loading more…');
          }
          final order = _orders[index];
          if (widget.openOrders) {
            return SellerActiveOrderCard(
              key: ValueKey(order.id),
              order: order,
              onAction: widget.onAction ?? (_, __) async {},
              onOrderUpdated: widget.onOrderUpdated ?? (_) {},
              onPaymentConfirmed: widget.onPaymentConfirmed ?? () async {},
              onReject: _reject,
              onReadyBy: widget.onReadyBy ?? (_) async {},
              rejectBusy: _rejectingOrderId == order.id,
            );
          }
          return SellerPastOrderCard(
            order: order,
            onRefresh: widget.onOrderRefresh,
          );
        },
      ),
    );
  }
}
