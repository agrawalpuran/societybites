import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../web/web_page_frame.dart';
import '../widgets/app_header.dart';

class SellerPaymentReconciliationScreen extends StatefulWidget {
  const SellerPaymentReconciliationScreen({
    super.key,
    this.kitchenSellerId,
    this.readOnly = false,
  });

  /// Owner oversight: load another seller's kitchen (view-only).
  final String? kitchenSellerId;
  final bool readOnly;

  @override
  State<SellerPaymentReconciliationScreen> createState() =>
      _SellerPaymentReconciliationScreenState();
}

class _DrillFilter {
  const _DrillFilter({
    this.paymentPhase,
    this.locationType,
    this.societyId,
    this.buyerId,
    this.paymentMethod,
    required this.title,
  });

  final String? paymentPhase;
  final String? locationType;
  final String? societyId;
  final String? buyerId;
  final String? paymentMethod;
  final String title;
}

class _SellerPaymentReconciliationScreenState
    extends State<SellerPaymentReconciliationScreen> {
  static const _green = Color(0xFF0E5A47);
  static const _muted = Color(0xFF6A7774);
  static const _ink = Color(0xFF101617);

  static const _presetLabels = <String, String>{
    'today': 'Today',
    'yesterday': 'Yesterday',
    'last_7_days': 'Last 7 days',
    'this_month': 'This month',
    'custom': 'Custom',
  };

  String _preset = 'today';
  DateTimeRange? _customRange;
  bool _loadingSummary = true;
  String? _summaryError;
  Map<String, dynamic> _summary = const {};

  _DrillFilter? _drill;
  bool _loadingOrders = false;
  String? _ordersError;
  List<Map<String, dynamic>> _orders = [];
  int _ordersPage = 1;
  int _ordersTotal = 0;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _reminderSending = {};

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _ymd(DateTime date) {
    final local = date.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    return '${local.year}-$mm-$dd';
  }

  String? get _fromYmd =>
      _preset == 'custom' && _customRange != null ? _ymd(_customRange!.start) : null;
  String? get _toYmd =>
      _preset == 'custom' && _customRange != null ? _ymd(_customRange!.end) : null;

  String _money(dynamic value) {
    final n = (value is num) ? value.toDouble() : double.tryParse('$value') ?? 0;
    if (n == n.roundToDouble()) return '₹${n.toStringAsFixed(0)}';
    return '₹${n.toStringAsFixed(2)}';
  }

  Future<void> _loadSummary() async {
    setState(() {
      _loadingSummary = true;
      _summaryError = null;
    });
    try {
      final data = await ApiService.getSellerReconciliationSummary(
        preset: _preset,
        from: _fromYmd,
        to: _toYmd,
        kitchenSellerId: widget.kitchenSellerId,
      );
      if (!mounted) return;
      setState(() {
        _summary = data;
        _loadingSummary = false;
      });
      if (_drill != null) {
        await _loadOrders(reset: true);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingSummary = false;
        _summaryError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _loadOrders({required bool reset}) async {
    if (_drill == null) return;
    if (reset) {
      _ordersPage = 1;
      _orders = [];
    }
    setState(() {
      _loadingOrders = true;
      _ordersError = null;
    });
    try {
      final data = await ApiService.getSellerReconciliationOrders(
        preset: _preset,
        from: _fromYmd,
        to: _toYmd,
        paymentPhase: _drill!.paymentPhase,
        locationType: _drill!.locationType,
        societyId: _drill!.societyId,
        buyerId: _drill!.buyerId,
        paymentMethod: _drill!.paymentMethod,
        search: _searchQuery.isEmpty ? null : _searchQuery,
        page: _ordersPage,
        kitchenSellerId: widget.kitchenSellerId,
      );
      if (!mounted) return;
      final rows = (data['orders'] as List?)
              ?.map((e) => Map<String, dynamic>.from(e as Map))
              .toList() ??
          [];
      setState(() {
        if (reset) {
          _orders = rows;
        } else {
          _orders.addAll(rows);
        }
        _ordersTotal = (data['total'] as num?)?.toInt() ?? _orders.length;
        _loadingOrders = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingOrders = false;
        _ordersError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: now,
      initialDateRange: _customRange ??
          DateTimeRange(
            start: now.subtract(const Duration(days: 6)),
            end: now,
          ),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: _green),
          ),
          child: child!,
        );
      },
    );
    if (!mounted || picked == null) return;
    setState(() {
      _preset = 'custom';
      _customRange = picked;
    });
    await _loadSummary();
  }

  Future<void> _selectPreset(String preset) async {
    if (preset == 'custom') {
      await _pickCustomRange();
      return;
    }
    setState(() => _preset = preset);
    await _loadSummary();
  }

  void _openDrill(_DrillFilter filter) {
    setState(() => _drill = filter);
    _loadOrders(reset: true);
  }

  void _closeDrill() {
    setState(() {
      _drill = null;
      _orders = [];
      _searchQuery = '';
      _searchController.clear();
    });
  }

  Future<void> _sendReminder(String orderId) async {
    if (_reminderSending.contains(orderId)) return;
    setState(() => _reminderSending.add(orderId));
    try {
      final result = await ApiService.sendSellerPaymentReminder(orderId);
      if (!mounted) return;
      final notification = result['notification'];
      final msg = notification is Map
          ? (notification['message']?.toString() ?? 'Reminder recorded.')
          : 'Reminder sent.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      await _loadOrders(reset: true);
      await _loadSummary();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) {
        setState(() => _reminderSending.remove(orderId));
      }
    }
  }

  Future<void> _showOrderSheet(Map<String, dynamic> order) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final buyer = order['buyer'] is Map
            ? Map<String, dynamic>.from(order['buyer'] as Map)
            : <String, dynamic>{};
        final loc = order['location'] is Map
            ? Map<String, dynamic>.from(order['location'] as Map)
            : <String, dynamic>{};
        final items = (order['items'] as List?) ?? [];
        final locLabel = loc['type'] == 'society'
            ? (loc['societyName']?.toString() ?? 'Society')
            : 'Outside society · ${loc['buyerName'] ?? buyer['name'] ?? 'Customer'}';

        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(ctx).padding.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Order #${order['orderNumber'] ?? order['id']}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(locLabel, style: const TextStyle(color: _muted, fontSize: 13)),
              if (buyer['phone'] != null)
                Text(
                  '${buyer['name'] ?? ''} · ${buyer['phone']}',
                  style: const TextStyle(color: _muted, fontSize: 13),
                ),
              const SizedBox(height: 12),
              Text(
                'Payment: ${order['paymentPhase']} · ${order['paymentMethod']}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                'Total ${_money(order['total'])} · Outstanding ${_money(order['outstandingAmount'])}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              for (final row in items)
                if (row is Map)
                  Text(
                    '${row['quantity']}× ${row['name']}',
                    style: const TextStyle(fontSize: 14),
                  ),
              if (!widget.readOnly && order['paymentPhase'] == 'PENDING') ...[
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _reminderSending.contains(order['id'])
                      ? null
                      : () => _sendReminder(order['id'] as String),
                  style: FilledButton.styleFrom(backgroundColor: _green),
                  child: const Text('Send payment reminder'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _presetChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          for (final key in [
            'today',
            'yesterday',
            'last_7_days',
            'this_month',
            'custom',
          ])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: Text(_presetLabels[key] ?? key),
                selected: _preset == key,
                onSelected: (_) => _selectPreset(key),
                selectedColor: _green.withValues(alpha: 0.15),
                checkmarkColor: _green,
              ),
            ),
        ],
      ),
    );
  }

  Widget _summaryCard(String label, String value, {VoidCallback? onTap}) {
    final child = Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EBEA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: _muted)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: _ink,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14), child: child);
  }

  Widget _locationRow({
    required String title,
    required Map<String, dynamic> totals,
    required _DrillFilter drill,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        'Sales ${_money(totals['totalSales'])} · Collected ${_money(totals['collected'])} · '
        'Pending ${_money(totals['pending'])} (${totals['pendingOrderCount'] ?? 0} orders)',
        style: const TextStyle(fontSize: 12, color: _muted),
      ),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: () => _openDrill(drill),
    );
  }

  Widget _buildSummaryView() {
    if (_loadingSummary) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(color: _green),
        ),
      );
    }
    if (_summaryError != null) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Text(_summaryError!, style: const TextStyle(color: Colors.red)),
      );
    }

    final summary = _summary['summary'] is Map
        ? Map<String, dynamic>.from(_summary['summary'] as Map)
        : <String, dynamic>{};
    final byMethod = _summary['byPaymentMethod'] is Map
        ? Map<String, dynamic>.from(_summary['byPaymentMethod'] as Map)
        : <String, dynamic>{};
    final locations = _summary['locations'] is Map
        ? Map<String, dynamic>.from(_summary['locations'] as Map)
        : <String, dynamic>{};
    final societies = (locations['societies'] as List?) ?? [];
    final outside = (locations['outsideBuyers'] as List?) ?? [];
    final basis = _summary['basis'] is Map
        ? Map<String, dynamic>.from(_summary['basis'] as Map)
        : null;

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        const SizedBox(height: 8),
        _presetChips(),
        if (basis != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              basis['note']?.toString() ?? '',
              style: const TextStyle(fontSize: 11, color: _muted),
            ),
          ),
        ],
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.55,
            children: [
              _summaryCard('Total sales', _money(summary['totalSales'])),
              _summaryCard('Collected', _money(summary['collected'])),
              _summaryCard(
                'Pending',
                _money(summary['pending']),
                onTap: () => _openDrill(
                  const _DrillFilter(
                    paymentPhase: 'PENDING',
                    title: 'Pending payments',
                  ),
                ),
              ),
              _summaryCard(
                'Pending orders',
                '${summary['pendingOrderCount'] ?? 0}',
                onTap: () => _openDrill(
                  const _DrillFilter(
                    paymentPhase: 'PENDING',
                    title: 'Pending orders',
                  ),
                ),
              ),
            ],
          ),
        ),
        if (summary['collectedInPaymentPeriod'] != null) ...[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Collected in period (by payment date): '
              '${_money(summary['collectedInPaymentPeriod'])}',
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
          ),
        ],
        const SizedBox(height: 20),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'By payment method',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink),
          ),
        ),
        for (final entry in [
          ('upi', 'UPI'),
          ('cash', 'Cash / COD'),
        ])
          if (byMethod[entry.$1] is Map)
            _locationRow(
              title: entry.$2,
              totals: Map<String, dynamic>.from(byMethod[entry.$1] as Map),
              drill: _DrillFilter(
                paymentMethod: entry.$1,
                title: entry.$2,
              ),
            ),
        const SizedBox(height: 12),
        ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          title: const Text(
            'All orders',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _openDrill(const _DrillFilter(title: 'All orders')),
        ),
        const Divider(height: 1),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            'Societies',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink),
          ),
        ),
        if (societies.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text('No society orders in this period.', style: TextStyle(color: _muted)),
          ),
        for (final row in societies)
          if (row is Map)
            _locationRow(
              title: row['societyName']?.toString() ?? 'Society',
              totals: Map<String, dynamic>.from(row),
              drill: _DrillFilter(
                locationType: 'society',
                societyId: row['societyId']?.toString(),
                title: row['societyName']?.toString() ?? 'Society',
              ),
            ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Text(
            'Outside registered society',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: _ink),
          ),
        ),
        if (outside.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text('No outside-society orders in this period.', style: TextStyle(color: _muted)),
          ),
        for (final row in outside)
          if (row is Map)
            _locationRow(
              title: row['buyerName']?.toString() ?? 'Customer',
              totals: Map<String, dynamic>.from(row),
              drill: _DrillFilter(
                locationType: 'outside',
                buyerId: row['buyerId']?.toString(),
                title: row['buyerName']?.toString() ?? 'Customer',
              ),
            ),
      ],
    );
  }

  Widget _buildOrdersView() {
    final drill = _drill!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search order or customer',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear_rounded),
                onPressed: () {
                  _searchController.clear();
                  _searchQuery = '';
                  _loadOrders(reset: true);
                },
              ),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onSubmitted: (value) {
              _searchQuery = value.trim();
              _loadOrders(reset: true);
            },
          ),
        ),
        Expanded(
          child: _loadingOrders && _orders.isEmpty
              ? const Center(child: CircularProgressIndicator(color: _green))
              : _ordersError != null
                  ? Center(child: Text(_ordersError!))
                  : _orders.isEmpty
                      ? const Center(child: Text('No orders match these filters.'))
                      : RefreshIndicator(
                          color: _green,
                          onRefresh: () => _loadOrders(reset: true),
                          child: ListView.builder(
                            itemCount: _orders.length + (_orders.length < _ordersTotal ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= _orders.length) {
                                return TextButton(
                                  onPressed: () {
                                    _ordersPage += 1;
                                    _loadOrders(reset: false);
                                  },
                                  child: const Text('Load more'),
                                );
                              }
                              final order = _orders[index];
                              final buyer = order['buyer'] is Map
                                  ? Map<String, dynamic>.from(order['buyer'] as Map)
                                  : <String, dynamic>{};
                              return ListTile(
                                title: Text(
                                  '#${order['orderNumber'] ?? order['id']} · ${buyer['name'] ?? 'Customer'}',
                                  style: const TextStyle(fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  '${order['paymentPhase']} · ${_money(order['outstandingAmount'] ?? order['total'])} outstanding',
                                  style: const TextStyle(fontSize: 12, color: _muted),
                                ),
                                trailing: !widget.readOnly &&
                                        order['paymentPhase'] == 'PENDING'
                                    ? IconButton(
                                        icon: const Icon(Icons.notifications_active_outlined),
                                        tooltip: 'Send reminder',
                                        onPressed: () =>
                                            _sendReminder(order['id'] as String),
                                      )
                                    : const Icon(Icons.chevron_right_rounded),
                                onTap: () => _showOrderSheet(order),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final inDrill = _drill != null;
    final title =
        inDrill ? _drill!.title : 'Payments & Reconciliation';

    return centerOnWeb(
      context,
      Scaffold(
        backgroundColor: const Color(0xFFF7F8F8),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppHeader(
                padding: const EdgeInsets.fromLTRB(4, 10, 20, 0),
                showCart: false,
                leading: IconButton(
                  onPressed: () {
                    if (inDrill) {
                      _closeDrill();
                    } else {
                      Navigator.pop(context);
                    }
                  },
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  color: const Color(0xFF3A4644),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ),
              Expanded(
                child: inDrill ? _buildOrdersView() : _buildSummaryView(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
