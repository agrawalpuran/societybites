import 'package:flutter/material.dart';

import '../../services/api_service.dart';

class AdminPaymentSplitsScreen extends StatefulWidget {
  const AdminPaymentSplitsScreen({super.key});

  @override
  State<AdminPaymentSplitsScreen> createState() =>
      _AdminPaymentSplitsScreenState();
}

class _AdminPaymentSplitsScreenState extends State<AdminPaymentSplitsScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];

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
      final rows = await ApiService.getAdminPaymentSplits();
      if (!mounted) return;
      setState(() {
        _rows = rows;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAF9),
        elevation: 0,
        foregroundColor: const Color(0xFF101617),
        title: const Text('Seller payouts'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _rows.isEmpty
                      ? ListView(
                          children: const [
                            SizedBox(height: 80),
                            Center(
                              child: Text(
                                'No payouts are waiting.',
                                style: TextStyle(color: Color(0xFF6A7774)),
                              ),
                            ),
                          ],
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: _rows.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final row = _rows[index];
                            final share = row['sellerShare'];
                            return Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFFEAEFED)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${row['orderNumber'] ?? ''}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${row['sellerName'] ?? 'Seller'} · ₹$share · ${row['splitStatus']}',
                                    style: const TextStyle(color: Color(0xFF6A7774)),
                                  ),
                                  if (row['splitError'] != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '${row['splitError']}',
                                      style: const TextStyle(
                                        color: Color(0xFFD94F4F),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                  if (row['vendorStatus'] != null)
                                    Text(
                                      'Vendor ${row['vendorStatus']}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF6A7774),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
