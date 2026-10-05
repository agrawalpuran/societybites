import 'package:flutter/material.dart';

import '../../models/coupon.dart';
import '../../services/api_service.dart';
import '../../widgets/screen_loading_note.dart';

const _green = Color(0xFF0E5A47);

class AdminCouponSellerPayoutsScreen extends StatefulWidget {
  const AdminCouponSellerPayoutsScreen({super.key, this.loadReport});

  final Future<AdminCouponSellerPayoutReport> Function({
    DateTime? dateFrom,
    DateTime? dateTo,
    String? sellerId,
  })? loadReport;

  @override
  State<AdminCouponSellerPayoutsScreen> createState() =>
      _AdminCouponSellerPayoutsScreenState();
}

class _AdminCouponSellerPayoutsScreenState
    extends State<AdminCouponSellerPayoutsScreen> {
  late DateTime _dateFrom;
  late DateTime _dateTo;
  final _sellerId = TextEditingController();

  AdminCouponSellerPayoutReport? _report;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _dateTo = DateTime(now.year, now.month, now.day, 23, 59, 59);
    _dateFrom = _dateTo.subtract(const Duration(days: 30));
    _load();
  }

  @override
  void dispose() {
    _sellerId.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final load = widget.loadReport ?? ApiService.getAdminCouponSellerPayouts;
      final report = await load(
        dateFrom: _dateFrom,
        dateTo: _dateTo,
        sellerId: _sellerId.text.trim().isEmpty ? null : _sellerId.text.trim(),
      );
      if (!mounted) return;
      setState(() => _report = report);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = ApiService.userFacingError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = isFrom ? _dateFrom : _dateTo;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isFrom) {
        _dateFrom = DateTime(picked.year, picked.month, picked.day);
      } else {
        _dateTo = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      }
    });
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _report == null) {
      return const ScreenLoadingNote(message: 'Loading seller payouts…');
    }

    final report = _report;
    return RefreshIndicator(
      color: _green,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          const Text(
            'Coupon subsidy owed to sellers (SocietyEats top-up per order).',
            style: TextStyle(color: Color(0xFF5C6B66), height: 1.35),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                onPressed: () => _pickDate(isFrom: true),
                child: Text('From ${formatCouponDate(_dateFrom)}'),
              ),
              OutlinedButton(
                onPressed: () => _pickDate(isFrom: false),
                child: Text('To ${formatCouponDate(_dateTo)}'),
              ),
              SizedBox(
                width: 200,
                child: TextField(
                  controller: _sellerId,
                  decoration: const InputDecoration(
                    labelText: 'Seller ID (optional)',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _load(),
                ),
              ),
              FilledButton(
                onPressed: _load,
                style: FilledButton.styleFrom(backgroundColor: _green),
                child: const Text('Apply'),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Color(0xFFB42318))),
          ],
          if (report != null) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                _SummaryChip(
                  label: 'Total top-up',
                  value: formatRupee(report.totalSubsidy),
                ),
                const SizedBox(width: 8),
                _SummaryChip(
                  label: 'Orders',
                  value: '${report.rowCount}',
                ),
              ],
            ),
            if (report.bySeller.isNotEmpty) ...[
              const SizedBox(height: 20),
              const Text(
                'By seller',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              for (final seller in report.bySeller)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 0,
                  color: const Color(0xFFF0F5F3),
                  child: ListTile(
                    title: Text(
                      seller.sellerName ?? seller.sellerId ?? 'Unknown seller',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      [
                        if (seller.sellerPhone != null) seller.sellerPhone!,
                        '${seller.orderCount} order${seller.orderCount == 1 ? '' : 's'}',
                      ].join(' · '),
                    ),
                    trailing: Text(
                      formatRupee(seller.subsidyTotal),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _green,
                      ),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 20),
            const Text(
              'By order',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (report.rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No redeemed coupons in this range')),
              )
            else
              for (final row in report.rows)
                Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  elevation: 0,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                row.orderNumber,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            Text(
                              formatRupee(row.subsidyAmount),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: _green,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          row.sellerName ?? row.sellerId ?? 'Seller unknown',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (row.sellerPhone != null)
                          Text(
                            row.sellerPhone!,
                            style: const TextStyle(
                              color: Color(0xFF5C6B66),
                              fontSize: 13,
                            ),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'Coupon ${row.couponCode} · '
                          'Food ${formatRupee(row.foodSubtotal)} · '
                          'Buyer paid ${formatRupee(row.buyerPaid)}',
                          style: const TextStyle(
                            color: Color(0xFF3B4745),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${formatCouponDate(row.createdAt)} · '
                          '${row.orderStatus} · payment ${row.paymentStatus}',
                          style: const TextStyle(
                            color: Color(0xFF6B7A75),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8E5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF6B7A75))),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ],
      ),
    );
  }
}
