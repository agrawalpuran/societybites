import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/api_service.dart';

String _humanizeStatus(String status) {
  if (status.isEmpty) return status;
  return status
      .split('_')
      .where((part) => part.isNotEmpty)
      .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
      .join(' ');
}

const _presetLabels = <String, String>{
  'today': 'Today',
  'last_7_days': 'Last 7 days',
  'last_30_days': 'Last 30 days',
  'this_month': 'This month',
  'custom': 'Custom',
};

typedef SellerInsightsFetcher = Future<Map<String, dynamic>> Function({
  required String preset,
  String? from,
  String? to,
});

class SellerInsightsPanel extends StatefulWidget {
  const SellerInsightsPanel({
    super.key,
    this.fetchInsights,
    this.showHeading = true,
    this.onSeeAllOrders,
  });

  final SellerInsightsFetcher? fetchInsights;
  final bool showHeading;
  final VoidCallback? onSeeAllOrders;

  @override
  State<SellerInsightsPanel> createState() => _SellerInsightsPanelState();
}

class _SellerInsightsPanelState extends State<SellerInsightsPanel> {
  static const _green = Color(0xFF0E5A47);
  static const _muted = Color(0xFF6A7774);
  static const _ink = Color(0xFF101617);

  String _preset = 'last_7_days';
  DateTimeRange? _customRange;
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _data = const {};

  SellerInsightsFetcher get _fetch =>
      widget.fetchInsights ?? ApiService.getSellerInsights;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _ymd(DateTime date) {
    final local = date.toLocal();
    final mm = local.month.toString().padLeft(2, '0');
    final dd = local.day.toString().padLeft(2, '0');
    return '${local.year}-$mm-$dd';
  }

  String get _rangeLabel {
    if (_preset == 'custom' && _customRange != null) {
      return '${_customRange!.start.day}/${_customRange!.start.month}'
          ' – ${_customRange!.end.day}/${_customRange!.end.month}';
    }
    return _presetLabels[_preset] ?? 'Last 7 days';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _fetch(
        preset: _preset,
        from: _preset == 'custom' && _customRange != null
            ? _ymd(_customRange!.start)
            : null,
        to: _preset == 'custom' && _customRange != null
            ? _ymd(_customRange!.end)
            : null,
      );
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
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
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: _green,
            ),
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
    await _load();
  }

  Future<void> _selectPreset(String preset) async {
    if (preset == 'custom') {
      await _pickCustomRange();
      return;
    }
    setState(() => _preset = preset);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.showHeading) ...[
            const Text(
              'Insights',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: _ink,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'How your kitchen performed in this period.',
              style: TextStyle(
                fontSize: 13,
                color: _muted,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: PopupMenuButton<String>(
              tooltip: 'Date range',
              onSelected: _selectPreset,
              itemBuilder: (context) => [
                for (final entry in _presetLabels.entries)
                  PopupMenuItem(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
              ],
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFEAEFED)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _rangeLabel,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _green,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down_rounded, color: _green),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(color: _green),
              ),
            )
          else if (_error != null)
            _ErrorCard(message: _error!, onRetry: _load)
          else
            _InsightsBody(
              data: _data,
              onSeeAllOrders: widget.onSeeAllOrders,
            ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Insights are unavailable right now.',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: const TextStyle(color: Color(0xFF6A7774), fontSize: 13),
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _InsightsBody extends StatelessWidget {
  const _InsightsBody({required this.data, this.onSeeAllOrders});

  final Map<String, dynamic> data;
  final VoidCallback? onSeeAllOrders;

  Map<String, dynamic> get summary =>
      Map<String, dynamic>.from(data['summary'] as Map? ?? const {});

  String get empty => data['empty']?.toString() ?? '';

  @override
  Widget build(BuildContext context) {
    if (empty == 'none') {
      return const _EmptyCard(
        title: 'No orders yet',
        body:
            'Your sales insights will appear here once customers start ordering.',
      );
    }
    if (empty == 'period') {
      return const _EmptyCard(
        title: 'No sales in this period',
        body: 'Try another date range to see earlier kitchen activity.',
      );
    }

    final orders = (summary['orders'] as num?)?.toInt() ?? 0;
    final sales = (summary['sales'] as num?)?.toDouble() ?? 0;
    final itemsSold = (summary['itemsSold'] as num?)?.toInt() ?? 0;
    final aov = (summary['averageOrderValue'] as num?)?.toDouble() ?? 0;
    final breakdown = (data['statusBreakdown'] as List?) ?? const [];
    final trend = (data['dailyTrend'] as List?) ?? const [];
    final topItems = (data['topItems'] as List?) ?? const [];
    final recent = (data['recentOrders'] as List?) ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: _KpiCard(label: 'Orders', value: '$orders')),
            const SizedBox(width: 10),
            Expanded(
              child: _KpiCard(label: 'Sales', value: _rupees(sales)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _KpiCard(label: 'Items sold', value: '$itemsSold'),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _KpiCard(label: 'Avg order', value: _rupees(aov)),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Sales & orders',
          child: _TrendChart(points: trend),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Order status',
          child: Column(
            children: [
              for (final row in breakdown)
                _StatusRow(
                  status: (row as Map)['status']?.toString() ?? '',
                  count: (row['count'] as num?)?.toInt() ?? 0,
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Top selling items',
          child: topItems.isEmpty
              ? const Text(
                  'No completed sales in this period yet.',
                  style: TextStyle(color: Color(0xFF6A7774), fontSize: 13),
                )
              : Column(
                  children: [
                    for (final item in topItems)
                      _TopItemRow(item: Map<String, dynamic>.from(item as Map)),
                  ],
                ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Recent orders',
          trailing: onSeeAllOrders == null
              ? null
              : TextButton(
                  onPressed: onSeeAllOrders,
                  child: const Text('See all'),
                ),
          child: recent.isEmpty
              ? const Text(
                  'No orders in this period.',
                  style: TextStyle(color: Color(0xFF6A7774), fontSize: 13),
                )
              : Column(
                  children: [
                    for (final order in recent)
                      _RecentOrderRow(
                        order: Map<String, dynamic>.from(order as Map),
                      ),
                  ],
                ),
        ),
      ],
    );
  }

  static String _rupees(double value) {
    if (value == value.roundToDouble()) {
      return '₹${value.toStringAsFixed(0)}';
    }
    return '₹${value.toStringAsFixed(2)}';
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              height: 1.4,
              color: Color(0xFF6A7774),
            ),
          ),
        ],
      ),
    );
  }
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6A7774),
            ),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF101617),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101617),
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.status, required this.count});

  final String status;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _humanizeStatus(status),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3A4644),
              ),
            ),
          ),
          Text(
            '$count',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopItemRow extends StatelessWidget {
  const _TopItemRow({required this.item});

  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final qty = (item['quantitySold'] as num?)?.toInt() ?? 0;
    final sales = (item['sales'] as num?)?.toDouble() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              item['name']?.toString() ?? 'Item',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF101617),
              ),
            ),
          ),
          Text(
            '$qty sold',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6A7774),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            _InsightsBody._rupees(sales),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: Color(0xFF0E5A47),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentOrderRow extends StatelessWidget {
  const _RecentOrderRow({required this.order});

  final Map<String, dynamic> order;

  @override
  Widget build(BuildContext context) {
    final created = DateTime.tryParse(order['createdAt']?.toString() ?? '');
    final amount = (order['amount'] as num?)?.toDouble() ?? 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order['orderNumber']?.toString() ?? '',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101617),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  order['buyerName']?.toString() ?? 'Neighbor',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6A7774),
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _InsightsBody._rupees(amount),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                _humanizeStatus(order['status']?.toString() ?? ''),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0E5A47),
                ),
              ),
              if (created != null)
                Text(
                  _formatWhen(created),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF6A7774)),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatWhen(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour > 12
        ? local.hour - 12
        : (local.hour == 0 ? 12 : local.hour);
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    final mm = local.minute.toString().padLeft(2, '0');
    return '${local.day}/${local.month} · $hour:$mm $ampm';
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points});

  final List<dynamic> points;

  @override
  Widget build(BuildContext context) {
    final parsed = points
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    if (parsed.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text(
          'No activity to chart yet.',
          style: TextStyle(color: Color(0xFF6A7774)),
        ),
      );
    }

    final maxOrders = parsed.fold<int>(
      0,
      (max, row) => math.max(max, (row['orders'] as num?)?.toInt() ?? 0),
    );
    final maxSales = parsed.fold<double>(
      0,
      (max, row) => math.max(max, (row['sales'] as num?)?.toDouble() ?? 0),
    );
    final yMax = math.max(4, maxOrders);
    final salesMax = maxSales <= 0 ? 100.0 : maxSales;
    final yTicks = <int>[yMax, (yMax / 2).round(), 0];
    final xStep = parsed.length <= 8
        ? 1
        : parsed.length <= 16
            ? 2
            : (parsed.length / 7).ceil();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            _LegendSwatch(color: Color(0xFFD4EDDF), border: Color(0xFF0E5A47)),
            SizedBox(width: 6),
            Text(
              'Orders',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3A4644),
              ),
            ),
            SizedBox(width: 14),
            _LegendLine(),
            SizedBox(width: 6),
            Text(
              'Sales (₹)',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF3A4644),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 196,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 28,
                child: Column(
                  children: [
                    const Text(
                      'Orders',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6A7774),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (final tick in yTicks)
                            Text(
                              '$tick',
                              style: const TextStyle(
                                fontSize: 10,
                                color: Color(0xFF6A7774),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: CustomPaint(
                        painter: _TrendPainter(
                          points: parsed,
                          maxOrders: yMax.toDouble(),
                          maxSales: salesMax,
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        for (var i = 0; i < parsed.length; i++)
                          Expanded(
                            child: Text(
                              i % xStep == 0
                                  ? _dayLabel(parsed[i]['date']?.toString())
                                  : '',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6A7774),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                width: 36,
                child: Column(
                  children: [
                    const Text(
                      '₹',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF6A7774),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _salesTick(salesMax),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF6A7774),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _salesTick(salesMax / 2),
                            style: const TextStyle(
                              fontSize: 10,
                              color: Color(0xFF6A7774),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Text(
                            '0',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF6A7774),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _dayLabel(String? ymd) {
    if (ymd == null || ymd.length < 10) return '';
    final day = int.tryParse(ymd.substring(8, 10));
    return day == null ? '' : '$day';
  }

  static String _salesTick(double value) {
    if (value >= 1000) return '${(value / 1000).toStringAsFixed(value >= 10000 ? 0 : 1)}k';
    return value.round().toString();
  }
}

class _LegendSwatch extends StatelessWidget {
  const _LegendSwatch({required this.color, required this.border});

  final Color color;
  final Color border;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: border, width: 1),
      ),
    );
  }
}

class _LegendLine extends StatelessWidget {
  const _LegendLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 3,
      decoration: BoxDecoration(
        color: const Color(0xFF0E5A47),
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.maxOrders,
    required this.maxSales,
  });

  final List<Map<String, dynamic>> points;
  final double maxOrders;
  final double maxSales;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFEAEFED)
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final y = size.height * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final axisPaint = Paint()
      ..color = const Color(0xFFC5CFCB)
      ..strokeWidth = 1.2;
    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      axisPaint,
    );
    canvas.drawLine(Offset.zero, Offset(0, size.height), axisPaint);

    final n = points.length;
    if (n == 0) return;
    final slot = size.width / n;
    final barPaint = Paint()..color = const Color(0xFFD4EDDF);
    final barBorder = Paint()
      ..color = const Color(0xFF0E5A47)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = const Color(0xFF0E5A47)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    final pointPaint = Paint()..color = const Color(0xFF0E5A47);
    final path = Path();

    for (var i = 0; i < n; i++) {
      final orders = (points[i]['orders'] as num?)?.toDouble() ?? 0;
      final sales = (points[i]['sales'] as num?)?.toDouble() ?? 0;
      final barH = maxOrders <= 0 ? 0.0 : (orders / maxOrders) * size.height;
      final x = slot * i + slot * 0.22;
      final barW = slot * 0.56;
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, size.height - barH, barW, barH),
        const Radius.circular(4),
      );
      canvas.drawRRect(rect, barPaint);
      canvas.drawRRect(rect, barBorder);

      final py = size.height -
          (maxSales <= 0 ? 0 : (sales / maxSales) * size.height);
      final px = x + barW / 2;
      if (i == 0) {
        path.moveTo(px, py);
      } else {
        path.lineTo(px, py);
      }
      canvas.drawCircle(Offset(px, py), 3, pointPaint);
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.maxOrders != maxOrders ||
      oldDelegate.maxSales != maxSales;
}
