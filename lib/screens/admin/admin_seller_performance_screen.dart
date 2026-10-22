import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/api_service.dart';
import '../../widgets/admin_loading_panel.dart';

String _formatIstYmd(DateTime date) {
  final local = DateTime(date.year, date.month, date.day);
  final y = local.year.toString().padLeft(4, '0');
  final m = local.month.toString().padLeft(2, '0');
  final d = local.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

class AdminSellerPerformanceScreen extends StatefulWidget {
  const AdminSellerPerformanceScreen({super.key});

  @override
  State<AdminSellerPerformanceScreen> createState() =>
      _AdminSellerPerformanceScreenState();
}

class _AdminSellerPerformanceScreenState
    extends State<AdminSellerPerformanceScreen> {
  static const _presets = <String, String>{
    'last_7_days': '7 days',
    'last_30_days': '30 days',
    'all_time': 'All time',
    'custom': 'Custom',
  };

  String _preset = 'last_7_days';
  String _sort = 'netFoodSales';
  DateTime? _customFrom;
  DateTime? _customTo;
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _sellers = [];
  List<Map<String, dynamic>> _campaigns = [];
  bool _loading = true;
  String? _error;

  String? get _fromYmd =>
      _preset == 'custom' && _customFrom != null ? _formatIstYmd(_customFrom!) : null;

  String? get _toYmd =>
      _preset == 'custom' && _customTo != null ? _formatIstYmd(_customTo!) : null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_preset == 'custom' && (_customFrom == null || _customTo == null)) {
      setState(() {
        _loading = false;
        _error = null;
        _summary = null;
        _sellers = [];
        _campaigns = [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        ApiService.getAdminPerformanceSummary(
          preset: _preset,
          from: _fromYmd,
          to: _toYmd,
        ),
        ApiService.getAdminPerformanceSellers(
          preset: _preset,
          from: _fromYmd,
          to: _toYmd,
          sort: _sort,
          limit: 50,
        ),
        ApiService.getAdminPerformanceCampaigns(
          preset: _preset,
          from: _fromYmd,
          to: _toYmd,
        ),
      ]);
      if (!mounted) return;
      final summary = results[0] as Map<String, dynamic>;
      final board = results[1] as Map<String, dynamic>;
      final campaigns = results[2] as Map<String, dynamic>;
      setState(() {
        _summary = summary;
        _sellers = (board['sellers'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _campaigns = (campaigns['campaigns'] as List<dynamic>? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initialStart = _customFrom ?? now.subtract(const Duration(days: 6));
    final initialEnd = _customTo ?? now;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: now,
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      helpText: 'Select range (IST dates)',
    );
    if (picked == null) return;
    setState(() {
      _preset = 'custom';
      _customFrom = picked.start;
      _customTo = picked.end;
    });
    _load();
  }

  Future<void> _exportCsv() async {
    try {
      final csv = await ApiService.getAdminPerformanceExportCsv(
        preset: _preset,
        sort: _sort,
        from: _fromYmd,
        to: _toYmd,
      );
      await Clipboard.setData(ClipboardData(text: csv));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seller performance CSV copied to clipboard'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e')),
      );
    }
  }

  void _onPreset(String preset) {
    if (preset == _preset) return;
    if (preset == 'custom') {
      _pickCustomRange();
      return;
    }
    setState(() => _preset = preset);
    _load();
  }

  void _onSort(String sort) {
    if (sort == _sort) return;
    setState(() => _sort = sort);
    _load();
  }

  Future<void> _openSeller(String sellerId, String name) async {
    try {
      final detail = await ApiService.getAdminPerformanceSellerDetail(
        sellerId,
        preset: _preset,
        from: _fromYmd,
        to: _toYmd,
      );
      final orders = await ApiService.getAdminPerformanceSellerOrders(
        sellerId,
        preset: _preset,
        from: _fromYmd,
        to: _toYmd,
        limit: 20,
      );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _SellerDetailSheet(
          sellerName: name,
          detail: detail,
          orders: (orders['orders'] as List<dynamic>? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load seller: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AdminLoadingPanel(message: 'Loading seller performance…');
    }
    if (_preset == 'custom' && (_customFrom == null || _customTo == null)) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Choose a custom date range to load metrics.'),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _pickCustomRange,
                child: const Text('Pick dates'),
              ),
            ],
          ),
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    final summary = _summary?['summary'] as Map<String, dynamic>? ?? {};
    final range = _summary?['dateRange'] as Map<String, dynamic>? ?? {};
    final patterns =
        _summary?['patternSignals'] as Map<String, dynamic>? ?? {};
    final truncated = _summary?['truncated'] == true;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Seller performance',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101617),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _exportCsv,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('CSV'),
              ),
            ],
          ),
          Text(
            '${range['from'] ?? ''} → ${range['to'] ?? ''} (IST)',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6A7774)),
          ),
          if (_preset == 'custom')
            TextButton(
              onPressed: _pickCustomRange,
              child: const Text('Change custom range'),
            ),
          if (truncated)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Large range: metrics use the most recent 5,000 orders in range.',
                style: TextStyle(fontSize: 12, color: Color(0xFFB54708)),
              ),
            ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presets.entries
                .map(
                  (e) => ChoiceChip(
                    label: Text(e.value),
                    selected: _preset == e.key,
                    onSelected: (_) => _onPreset(e.key),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          _KpiGrid(summary: summary),
          const SizedBox(height: 20),
          _PatternSignalsPanel(patterns: patterns),
          const SizedBox(height: 20),
          const Text(
            'SELLER LEADERBOARD',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8A9491),
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap a seller for payment mix, cancel reasons, and order list. '
            'Use Admin → Orders for full buyer phone and audit.',
            style: TextStyle(fontSize: 11, color: Color(0xFF8A9491), height: 1.3),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              _SortChip(
                label: 'Net food',
                value: 'netFoodSales',
                selected: _sort,
                onSelect: _onSort,
              ),
              _SortChip(
                label: 'Orders',
                value: 'qualifyingOrders',
                selected: _sort,
                onSelect: _onSort,
              ),
              _SortChip(
                label: 'Buyers',
                value: 'uniqueBuyers',
                selected: _sort,
                onSelect: _onSort,
              ),
              _SortChip(
                label: 'Cancel rate',
                value: 'cancellationRate',
                selected: _sort,
                onSelect: _onSort,
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_sellers.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No seller activity in this period.',
                style: TextStyle(color: Color(0xFF8A9491)),
              ),
            )
          else
            ..._sellers.map((row) => _SellerLeaderboardTile(
                  row: row,
                  onTap: () => _openSeller(
                    row['sellerId'] as String,
                    row['sellerName']?.toString() ?? 'Seller',
                  ),
                )),
          const SizedBox(height: 24),
          const Text(
            'PRE-ORDER CAMPAIGNS',
            style: TextStyle(
              fontSize: 12,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8A9491),
            ),
          ),
          const SizedBox(height: 8),
          if (_campaigns.isEmpty)
            const Text(
              'No pre-order campaign orders in this period.',
              style: TextStyle(color: Color(0xFF8A9491)),
            )
          else
            ..._campaigns.map((c) => _CampaignTile(row: c)),
        ],
      ),
    );
  }
}

class _PatternSignalsPanel extends StatelessWidget {
  const _PatternSignalsPanel({required this.patterns});

  final Map<String, dynamic> patterns;

  @override
  Widget build(BuildContext context) {
    final counts = patterns['counts'] as Map<String, dynamic>? ?? {};
    final highlights = (patterns['highlights'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final stuck = (patterns['paymentStuckOrders'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PATTERNS & REVIEW SIGNALS',
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w700,
            color: Color(0xFF8A9491),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          patterns['disclaimer']?.toString() ??
              'Heuristics for manual review only.',
          style: const TextStyle(fontSize: 11, color: Color(0xFF6A7774), height: 1.35),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _SignalChip(
              label: 'UPI awaiting seller',
              value: '${counts['buyerMarkedAwaitingSeller'] ?? 0}',
            ),
            _SignalChip(
              label: 'Stuck >24h',
              value: '${counts['paymentStuckOver24h'] ?? 0}',
            ),
            _SignalChip(
              label: 'High coupon %',
              value: '${counts['highDiscountOrders'] ?? 0}',
            ),
            _SignalChip(
              label: 'Repeat cancel buyers',
              value: '${counts['repeatIssueBuyers'] ?? 0}',
            ),
          ],
        ),
        if (highlights.isEmpty && stuck.isEmpty)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'No elevated signals in this period.',
              style: TextStyle(color: Color(0xFF8A9491)),
            ),
          ),
        ...highlights.map(
          (h) => Card(
            margin: const EdgeInsets.only(top: 8),
            color: h['severity'] == 'high'
                ? const Color(0xFFFFF4F4)
                : const Color(0xFFFFFBF0),
            child: ListTile(
              dense: true,
              leading: Icon(
                Icons.flag_outlined,
                color: h['severity'] == 'high'
                    ? const Color(0xFFB42318)
                    : const Color(0xFFB54708),
                size: 20,
              ),
              title: Text(
                h['message']?.toString() ?? '',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              subtitle: Text(
                h['code']?.toString() ?? '',
                style: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ),
        if (stuck.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'Payment marked, seller not confirmed (>24h)',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          ...stuck.map(
            (o) => Text(
              '#${o['orderNumber']} · ${o['sellerName']} · ${o['status']} · ₹${o['subtotal']}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6A7774)),
            ),
          ),
        ],
      ],
    );
  }
}

class _SignalChip extends StatelessWidget {
  const _SignalChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE3E8E4)),
      ),
      child: Text('$label: $value', style: const TextStyle(fontSize: 12)),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _KpiCard('Net food sales', '₹${summary['netFoodSales'] ?? 0}'),
      _KpiCard('Gross food sales', '₹${summary['grossFoodSales'] ?? 0}'),
      _KpiCard('Delivery (total)', '₹${summary['deliveryCharges'] ?? 0}'),
      _KpiCard('Completed orders', '${summary['qualifyingOrders'] ?? 0}'),
      _KpiCard('Unique buyers', '${summary['uniqueBuyers'] ?? 0}'),
      _KpiCard(
        'Cancel rate',
        '${(((summary['cancellationRate'] as num?) ?? 0) * 100).toStringAsFixed(0)}%',
      ),
      _KpiCard(
        'Avg net order',
        '₹${summary['averageNetFoodOrderValue'] ?? 0}',
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cols = width > 900 ? 3 : 2;
        final gap = 10.0;
        final cardWidth = (width - (cols - 1) * gap) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final card in cards)
              SizedBox(width: cardWidth, child: card),
          ],
        );
      },
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3E8E4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Color(0xFF6A7774)),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.value,
    required this.selected,
    required this.onSelect,
  });

  final String label;
  final String value;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected == value,
      onSelected: (_) => onSelect(value),
    );
  }
}

class _SellerLeaderboardTile extends StatelessWidget {
  const _SellerLeaderboardTile({required this.row, required this.onTap});

  final Map<String, dynamic> row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rate = (row['cancellationRate'] as num?)?.toDouble() ?? 0;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        title: Text(
          row['sellerName']?.toString() ?? 'Seller',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          'Net ₹${row['netFoodSales']} · ${row['qualifyingOrders']} orders · '
          '${row['uniqueBuyers']} buyers · cancel ${(rate * 100).toStringAsFixed(0)}%',
        ),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}

class _CampaignTile extends StatelessWidget {
  const _CampaignTile({required this.row});

  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(row['title']?.toString() ?? 'Campaign'),
        subtitle: Text(
          '${row['completedOrders']}/${row['ordersPlaced']} completed · '
          'Net ₹${row['netFoodSales']}',
        ),
      ),
    );
  }
}

class _SellerDetailSheet extends StatelessWidget {
  const _SellerDetailSheet({
    required this.sellerName,
    required this.detail,
    required this.orders,
  });

  final String sellerName;
  final Map<String, dynamic> detail;
  final List<Map<String, dynamic>> orders;

  @override
  Widget build(BuildContext context) {
    final metrics = detail['metrics'] as Map<String, dynamic>?;
    final statusCounts = detail['statusCounts'] as Map<String, dynamic>? ?? {};
    final paymentCounts =
        detail['paymentStatusCounts'] as Map<String, dynamic>? ?? {};
    final patterns =
        detail['patternSignals'] as Map<String, dynamic>? ?? {};
    final cancelReasons =
        patterns['cancelReasons'] as Map<String, dynamic>? ?? {};
    final flagged = (patterns['recentFlaggedOrders'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.65,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Material(
          child: ListView(
            controller: scrollController,
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                sellerName,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (metrics != null) ...[
                const SizedBox(height: 12),
                Text('Net food: ₹${metrics['netFoodSales']}'),
                Text('Gross food: ₹${metrics['grossFoodSales']}'),
                Text('Delivery: ₹${metrics['deliveryCharges']}'),
                Text('New buyers: ${metrics['newBuyers']}'),
                Text('Repeat buyers: ${metrics['repeatBuyers']}'),
                Text(
                  'Cancel rate: ${(((metrics['cancellationRate'] as num?) ?? 0) * 100).toStringAsFixed(0)}%',
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Payment status mix',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              ...paymentCounts.entries.map((e) => Text('${e.key}: ${e.value}')),
              const SizedBox(height: 12),
              const Text(
                'Order status mix',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              ...statusCounts.entries.map((e) => Text('${e.key}: ${e.value}')),
              if (cancelReasons.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Cancel / reject reasons',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                ...cancelReasons.entries.map((e) => Text('${e.key}: ${e.value}')),
              ],
              if (flagged.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  'Flagged orders (sample)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                ...flagged.map(
                  (o) => Text(
                    '#${o['orderNumber']} · ${o['status']} · ${o['paymentStatus']} · '
                    '₹${o['subtotal']} · ${o['buyerName']}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Orders in range',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              ...orders.map(
                (o) => Text(
                  '#${o['orderNumber']} · ${o['status']} · net ₹${o['netFood']} · '
                  '${o['paymentMethod']} / ${o['paymentStatus']}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
