import 'package:flutter/material.dart';

import '../../services/api_service.dart';

class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  String _statusFilter = '';
  List<Map<String, dynamic>> _orders = [];
  bool _isLoading = true;
  String? _error;
  int _page = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders({bool reset = true}) async {
    if (reset) {
      setState(() {
        _page = 1;
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final data = await ApiService.getAdminOrders(
        status: _statusFilter.isNotEmpty ? _statusFilter : null,
        page: _page,
      );
      if (!mounted) return;
      setState(() {
        if (reset) {
          _orders = data;
        } else {
          _orders.addAll(data);
        }
        _hasMore = data.length >= 20;
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

  void _loadMore() {
    if (!_hasMore || _isLoading) return;
    _page++;
    _loadOrders(reset: false);
  }

  void _onStatusChanged(String status) {
    _statusFilter = status;
    _loadOrders();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              '',
              'pending',
              'confirmed',
              'ready',
              'picked_up',
              'completed',
              'cancelled'
            ].map((status) {
              final isActive = _statusFilter == status;
              final label = status.isEmpty
                  ? 'All'
                  : status[0].toUpperCase() +
                      status.substring(1).replaceAll('_', ' ');
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  selected: isActive,
                  label: Text(label),
                  selectedColor: const Color(0xFFE8F5EE),
                  checkmarkColor: const Color(0xFF0E5A47),
                  onSelected: (_) => _onStatusChanged(status),
                ),
              );
            }).toList(),
          ),
        ),
        Expanded(child: _buildContent()),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading && _orders.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
      );
    }
    if (_error != null && _orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Color(0xFF6A7774))),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadOrders, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_orders.isEmpty) {
      return const Center(
        child: Text('No orders found',
            style: TextStyle(color: Color(0xFF6A7774))),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF0E5A47),
      onRefresh: _loadOrders,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _orders.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _orders.length) {
            _loadMore();
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
              ),
            );
          }

          final order = _orders[index];
          final orderNumber =
              order['orderNumber']?.toString() ?? order['id']?.toString() ?? '—';
          final buyer =
              (order['buyer'] as Map<String, dynamic>?)?['name']?.toString() ??
                  '—';
          final seller =
              (order['seller'] as Map<String, dynamic>?)?['name']?.toString() ??
                  '—';
          final total = order['total'] ?? order['totalAmount'] ?? 0;
          final status = order['status']?.toString() ?? 'pending';
          final createdAt = order['createdAt']?.toString() ?? '';

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '#$orderNumber',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: Color(0xFF101617),
                        ),
                      ),
                      const Spacer(),
                      _StatusBadge(status: status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 14, color: Color(0xFF8A9491)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Buyer: $buyer',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF6A7774)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Icon(Icons.storefront,
                          size: 14, color: Color(0xFF8A9491)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Seller: $seller',
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF6A7774)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        '₹$total',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: Color(0xFF0E5A47),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        _formatDate(createdAt),
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF8A9491)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(String iso) {
    if (iso.isEmpty) return '—';
    try {
      final d = DateTime.parse(iso);
      return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});
  final String status;

  Color get _color {
    switch (status) {
      case 'completed':
        return const Color(0xFF2E7D32);
      case 'cancelled':
        return const Color(0xFFC62828);
      case 'pending':
        return const Color(0xFFF57C00);
      case 'confirmed':
      case 'ready':
        return const Color(0xFF1565C0);
      default:
        return const Color(0xFF6A7774);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status[0].toUpperCase() + status.substring(1).replaceAll('_', ' '),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: _color,
        ),
      ),
    );
  }
}
