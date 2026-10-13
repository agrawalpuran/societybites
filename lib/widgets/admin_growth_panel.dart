import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';

/// Read-only signup / seller-enable trends for admin console (super + view-only).
class AdminGrowthPanel extends StatefulWidget {
  const AdminGrowthPanel({super.key});

  @override
  State<AdminGrowthPanel> createState() => _AdminGrowthPanelState();
}

class _AdminGrowthPanelState extends State<AdminGrowthPanel> {
  static const _ranges = <String, String>{
    'day': 'Daily',
    'week': 'Weekly',
    'month': 'Monthly',
    'quarter': 'Quarterly',
    'half_year': 'Half-year',
    'year': 'Yearly',
  };

  String _range = 'week';
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getAdminGrowth(range: _range);
      if (!mounted) return;
      setState(() {
        _data = data;
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

  void _selectRange(String range) {
    if (range == _range) return;
    setState(() => _range = range);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'GROWTH (IST)',
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 1.4,
            fontWeight: FontWeight.w700,
            color: Color(0xFF8A9491),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'New accounts use signup date. New sellers use enable-selling (terms) date.',
          style: TextStyle(
            fontSize: 12,
            height: 1.35,
            fontWeight: FontWeight.w500,
            color: Color(0xFF6A7774),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _ranges.entries.map((entry) {
            final selected = entry.key == _range;
            return ChoiceChip(
              key: Key('admin-growth-range-${entry.key}'),
              label: Text(entry.value),
              selected: selected,
              onSelected: (_) => _selectRange(entry.key),
              selectedColor: const Color(0xFFD4E8DF),
              labelStyle: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected
                    ? const Color(0xFF0E5A47)
                    : const Color(0xFF3A4644),
              ),
              side: BorderSide(
                color: selected
                    ? const Color(0xFF0E5A47)
                    : const Color(0xFFEAEFED),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Color(0xFF0E5A47),
                ),
              ),
            ),
          )
        else if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _error!,
                  style: const TextStyle(color: Color(0xFFD94F4F)),
                ),
                TextButton(onPressed: _load, child: const Text('Retry')),
              ],
            ),
          )
        else if (_data != null)
          _GrowthBody(data: _data!),
      ],
    );
  }
}

Future<void> _showGrowthMembersSheet({
  required BuildContext context,
  required String metric,
  required String title,
  required String periodLabel,
  required String start,
  required String end,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return _GrowthMembersSheet(
        metric: metric,
        title: title,
        periodLabel: periodLabel,
        start: start,
        end: end,
      );
    },
  );
}

class _GrowthMembersSheet extends StatefulWidget {
  const _GrowthMembersSheet({
    required this.metric,
    required this.title,
    required this.periodLabel,
    required this.start,
    required this.end,
  });

  final String metric;
  final String title;
  final String periodLabel;
  final String start;
  final String end;

  @override
  State<_GrowthMembersSheet> createState() => _GrowthMembersSheetState();
}

class _GrowthMembersSheetState extends State<_GrowthMembersSheet> {
  List<Map<String, dynamic>>? _members;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final members = await ApiService.getAdminGrowthMembers(
        metric: widget.metric,
        start: widget.start,
        end: widget.end,
      );
      if (!mounted) return;
      setState(() {
        _members = members;
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

  Future<void> _copyPhone(String phone) async {
    await Clipboard.setData(ClipboardData(text: phone));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Phone copied')),
    );
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      await _copyPhone(phone);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.75;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFEAEFED),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF101617),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.periodLabel,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6A7774),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFF0E5A47),
                    ),
                  ),
                ),
              )
            else if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFD94F4F)),
                    ),
                    TextButton(onPressed: _load, child: const Text('Retry')),
                  ],
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: _members == null || _members!.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Text(
                          'No one in this period.',
                          style: TextStyle(color: Color(0xFF6A7774)),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _members!.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: Color(0xFFF0F2F1)),
                        itemBuilder: (context, index) {
                          final m = _members![index];
                          final name =
                              (m['name']?.toString().trim().isNotEmpty == true)
                              ? m['name'].toString()
                              : 'No name';
                          final phone = m['phone']?.toString() ?? '—';
                          final role = m['role']?.toString();
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF101617),
                              ),
                            ),
                            subtitle: Text(
                              [
                                phone,
                                if (role != null && role.isNotEmpty)
                                  role,
                              ].join(' • '),
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF6A7774),
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Copy phone',
                                  icon: const Icon(Icons.copy_rounded, size: 20),
                                  onPressed: phone == '—'
                                      ? null
                                      : () => _copyPhone(phone),
                                ),
                                IconButton(
                                  tooltip: 'Call',
                                  icon: const Icon(
                                    Icons.phone_outlined,
                                    size: 20,
                                    color: Color(0xFF0E5A47),
                                  ),
                                  onPressed: phone == '—'
                                      ? null
                                      : () => _callPhone(phone),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _GrowthBody extends StatelessWidget {
  const _GrowthBody({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final summary = data['summary'] as Map<String, dynamic>? ?? {};
    final rangeStart = data['start']?.toString();
    final rangeEnd = data['end']?.toString();
    final series = (data['series'] as List<dynamic>? ?? [])
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final cross = constraints.maxWidth > 520 ? 3 : 1;
            final cards = [
              _SummaryTile(
                label: 'New accounts',
                value: (summary['newAccounts'] as num?)?.toInt() ?? 0,
                icon: Icons.person_add_alt_1_rounded,
                metric: 'accounts',
                periodLabel: 'Full selected range',
                start: rangeStart,
                end: rangeEnd,
              ),
              _SummaryTile(
                label: 'New buyers (role)',
                value: (summary['newBuyers'] as num?)?.toInt() ?? 0,
                icon: Icons.shopping_bag_outlined,
                metric: 'buyers',
                periodLabel: 'Full selected range',
                start: rangeStart,
                end: rangeEnd,
              ),
              _SummaryTile(
                label: 'New sellers',
                value: (summary['newSellers'] as num?)?.toInt() ?? 0,
                icon: Icons.storefront_outlined,
                metric: 'sellers',
                periodLabel: 'Full selected range',
                start: rangeStart,
                end: rangeEnd,
              ),
            ];
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: cards.map((card) {
                final width = cross == 1
                    ? constraints.maxWidth
                    : (constraints.maxWidth - (cross - 1) * 12) / cross;
                return SizedBox(width: width, child: card);
              }).toList(),
            );
          },
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFEAEFED)),
          ),
          child: Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        'Period',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF8A9491),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Accounts',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF8A9491),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Buyers',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF8A9491),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Sellers',
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF8A9491),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Color(0xFFEAEFED)),
              if (series.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No data in this range.',
                    style: TextStyle(color: Color(0xFF6A7774)),
                  ),
                )
              else
                ...series.map((row) {
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text(
                                row['label']?.toString() ?? '—',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF101617),
                                ),
                              ),
                            ),
                            Expanded(
                              child: _GrowthCountCell(
                                count: row['newAccounts'] as int? ??
                                    int.tryParse(
                                      '${row['newAccounts']}',
                                    ) ??
                                    0,
                                metric: 'accounts',
                                title: 'New accounts',
                                periodLabel:
                                    row['label']?.toString() ?? 'Period',
                                start: row['start']?.toString(),
                                end: row['end']?.toString(),
                              ),
                            ),
                            Expanded(
                              child: _GrowthCountCell(
                                count: row['newBuyers'] as int? ??
                                    int.tryParse('${row['newBuyers']}') ??
                                    0,
                                metric: 'buyers',
                                title: 'New buyers',
                                periodLabel:
                                    row['label']?.toString() ?? 'Period',
                                start: row['start']?.toString(),
                                end: row['end']?.toString(),
                              ),
                            ),
                            Expanded(
                              child: _GrowthCountCell(
                                count: row['newSellers'] as int? ??
                                    int.tryParse('${row['newSellers']}') ??
                                    0,
                                metric: 'sellers',
                                title: 'New sellers',
                                periodLabel:
                                    row['label']?.toString() ?? 'Period',
                                start: row['start']?.toString(),
                                end: row['end']?.toString(),
                                accent: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1, color: Color(0xFFF0F2F1)),
                    ],
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }
}

class _GrowthCountCell extends StatelessWidget {
  const _GrowthCountCell({
    required this.count,
    required this.metric,
    required this.title,
    required this.periodLabel,
    required this.start,
    required this.end,
    this.accent = false,
  });

  final int count;
  final String metric;
  final String title;
  final String periodLabel;
  final String? start;
  final String? end;
  final bool accent;

  bool get _canOpen =>
      count > 0 &&
      start != null &&
      start!.isNotEmpty &&
      end != null &&
      end!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: FontWeight.w700,
      color: accent ? const Color(0xFF0E5A47) : const Color(0xFF101617),
      decoration: _canOpen ? TextDecoration.underline : null,
      decorationColor: accent ? const Color(0xFF0E5A47) : const Color(0xFF101617),
    );

    final child = Text('$count', textAlign: TextAlign.end, style: style);

    if (!_canOpen) {
      return Align(alignment: Alignment.centerRight, child: child);
    }

    return Align(
      alignment: Alignment.centerRight,
      child: InkWell(
        onTap: () => _showGrowthMembersSheet(
          context: context,
          metric: metric,
          title: title,
          periodLabel: periodLabel,
          start: start!,
          end: end!,
        ),
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: child,
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.metric,
    required this.periodLabel,
    required this.start,
    required this.end,
  });

  final String label;
  final int value;
  final IconData icon;
  final String metric;
  final String periodLabel;
  final String? start;
  final String? end;

  bool get _canOpen =>
      value > 0 &&
      start != null &&
      start!.isNotEmpty &&
      end != null &&
      end!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      children: [
        Icon(icon, size: 20, color: const Color(0xFF0E5A47)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF101617),
                  decoration: _canOpen ? TextDecoration.underline : null,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6A7774),
                ),
              ),
              if (_canOpen)
                const Text(
                  'Tap to see contacts',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF0E5A47),
                  ),
                ),
            ],
          ),
        ),
      ],
    );

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: _canOpen
            ? () => _showGrowthMembersSheet(
                context: context,
                metric: metric,
                title: label,
                periodLabel: periodLabel,
                start: start!,
                end: end!,
              )
            : null,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEAEFED)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: content,
          ),
        ),
      ),
    );
  }
}
