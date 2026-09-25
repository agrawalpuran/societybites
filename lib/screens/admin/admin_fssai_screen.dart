import 'package:flutter/material.dart';

import '../../services/api_service.dart';

/// Admin view for submitted FSSAI details. Capture only — no approve/reject.
class AdminFssaiScreen extends StatefulWidget {
  const AdminFssaiScreen({super.key});

  @override
  State<AdminFssaiScreen> createState() => _AdminFssaiScreenState();
}

class _AdminFssaiScreenState extends State<AdminFssaiScreen> {
  bool _loading = true;
  String? _error;
  int _sellerCount = 0;
  int _submittedCount = 0;
  List<Map<String, dynamic>> _records = [];

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
      final data = await ApiService.getAdminFssai();
      if (!mounted) return;
      setState(() {
        _sellerCount = (data['sellerCount'] as num?)?.toInt() ?? 0;
        _submittedCount = (data['submittedCount'] as num?)?.toInt() ?? 0;
        final raw = data['records'];
        _records = raw is List
            ? raw
                  .whereType<Map>()
                  .map((item) => Map<String, dynamic>.from(item))
                  .toList()
            : [];
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
    if (_loading) {
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
              Text(_error!, style: const TextStyle(color: Color(0xFF6A7774))),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF0E5A47),
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'FSSAI',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Submitted licence details. Record view only — no approval yet.',
            style: TextStyle(
              color: Color(0xFF6A7774),
              height: 1.4,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '$_submittedCount of $_sellerCount sellers have submitted a licence',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF0E5A47),
            ),
          ),
          const SizedBox(height: 16),
          if (_records.isEmpty)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE6EBE9)),
              ),
              child: const Column(
                children: [
                  Icon(Icons.badge_outlined, size: 36, color: Color(0xFF0E5A47)),
                  SizedBox(height: 12),
                  Text(
                    'No FSSAI records yet',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: Color(0xFF101617),
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Sellers add their licence from Profile → FSSAI details.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF6A7774), height: 1.4),
                  ),
                ],
              ),
            )
          else
            ..._records.map(_recordCard),
        ],
      ),
    );
  }

  Widget _recordCard(Map<String, dynamic> row) {
    final fssai = row['fssai'] is Map
        ? Map<String, dynamic>.from(row['fssai'] as Map)
        : const <String, dynamic>{};
    final name = row['name']?.toString() ?? 'Seller';
    final society = row['societyName']?.toString();
    final number = fssai['number']?.toString() ?? '—';
    final registered = fssai['registeredName']?.toString();
    final expiry = fssai['expiry']?.toString();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                color: Color(0xFF101617),
              ),
            ),
            if (society != null && society.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(society, style: const TextStyle(color: Color(0xFF6A7774))),
            ],
            const SizedBox(height: 10),
            Text(
              number,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF0E5A47),
              ),
            ),
            if (registered != null && registered.isNotEmpty)
              Text(registered, style: const TextStyle(color: Color(0xFF6A7774))),
            if (expiry != null && expiry.isNotEmpty)
              Text(
                'Expires ${expiry.split('T').first}',
                style: const TextStyle(color: Color(0xFF6A7774), fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }
}
