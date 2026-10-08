import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../widgets/admin_loading_panel.dart';
import 'admin_address_proof_detail_screen.dart';

class AdminAddressProofScreen extends StatefulWidget {
  const AdminAddressProofScreen({super.key});

  @override
  State<AdminAddressProofScreen> createState() => _AdminAddressProofScreenState();
}

class _AdminAddressProofScreenState extends State<AdminAddressProofScreen> {
  static const _filters = <_ProofFilter>[
    _ProofFilter('PENDING', 'Pending'),
    _ProofFilter('OK', 'Looks fine'),
    _ProofFilter('FOLLOW_UP', 'Needs follow-up'),
  ];

  String _status = 'PENDING';
  List<Map<String, dynamic>> _records = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final records = await ApiService.getAdminAddressProofs(status: _status);
      if (!mounted) return;
      setState(() {
        _records = records;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load address proofs: $e')),
      );
    }
  }

  Future<void> _open(Map<String, dynamic> row) async {
    final id = row['userId']?.toString();
    if (id == null || id.isEmpty) return;
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminAddressProofDetailScreen(userId: id),
      ),
    );
    if (changed == true) await _load();
  }

  String _subtitle(Map<String, dynamic> row) {
    final society = row['societyName']?.toString();
    final block = row['block']?.toString();
    final flat = row['flatNumber']?.toString();
    final phone = row['phone']?.toString();
    final place = [
      if (block != null && block.isNotEmpty) block,
      if (flat != null && flat.isNotEmpty) flat,
    ].join(' ');
    return [
      if (society != null && society.isNotEmpty) society,
      if (place.isNotEmpty) place,
      if (phone != null && phone.isNotEmpty) phone,
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Compare the photo with the society and flat. Selling stays on.',
                style: TextStyle(fontSize: 13, color: Color(0xFF6A7774), height: 1.35),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final filter in _filters)
                    ChoiceChip(
                      label: Text(filter.label),
                      selected: _status == filter.status,
                      onSelected: _loading
                          ? null
                          : (_) {
                              if (_status == filter.status) return;
                              setState(() => _status = filter.status);
                              _load();
                            },
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return const AdminLoadingPanel(message: 'Loading address proofs…');
    }
    if (_records.isEmpty) {
      final message = _status == 'PENDING'
          ? 'No address proofs waiting for review'
          : 'No address proofs in this list';
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            const SizedBox(height: 80),
            Center(
              child: Text(message, style: const TextStyle(color: Color(0xFF6A7774))),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        itemCount: _records.length,
        itemBuilder: (context, index) {
          final row = _records[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: InkWell(
              onTap: () => _open(row),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row['name']?.toString() ?? 'Seller',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle(row),
                      style: const TextStyle(fontSize: 13, color: Color(0xFF6A7774)),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ProofFilter {
  const _ProofFilter(this.status, this.label);
  final String status;
  final String label;
}
