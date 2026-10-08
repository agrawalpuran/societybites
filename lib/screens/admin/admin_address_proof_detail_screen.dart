import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../web/web_page_frame.dart';

class AdminAddressProofDetailScreen extends StatefulWidget {
  const AdminAddressProofDetailScreen({super.key, required this.userId});

  final String userId;

  @override
  State<AdminAddressProofDetailScreen> createState() =>
      _AdminAddressProofDetailScreenState();
}

class _AdminAddressProofDetailScreenState extends State<AdminAddressProofDetailScreen> {
  Map<String, dynamic>? _record;
  bool _loading = true;
  bool _acting = false;
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
      final record = await ApiService.getAdminAddressProof(widget.userId);
      if (!mounted) return;
      setState(() {
        _record = record;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load address proof: $e';
      });
    }
  }

  Future<void> _mark(String status) async {
    setState(() => _acting = true);
    try {
      await ApiService.reviewAdminAddressProof(widget.userId, status: status);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _acting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save review: $e')),
      );
    }
  }

  String _place(Map<String, dynamic> record) {
    final block = record['block']?.toString();
    final flat = record['flatNumber']?.toString();
    final parts = [
      if (block != null && block.isNotEmpty) block,
      if (flat != null && flat.isNotEmpty) flat,
    ];
    return parts.isEmpty ? '—' : parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    return panelOnWeb(
      context,
      Scaffold(
        backgroundColor: const Color(0xFFF8FAF9),
        appBar: AppBar(
          backgroundColor: const Color(0xFF0E5A47),
          foregroundColor: Colors.white,
          title: const Text('Address proof', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        body: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: Color(0xFF0E5A47)));
    }
    if (_error != null || _record == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error ?? 'Address proof not found', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              TextButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    final record = _record!;
    final status = record['status']?.toString() ?? 'PENDING';
    final url = record['addressProofUrl']?.toString();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          record['name']?.toString() ?? 'Seller',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text('Phone: ${record['phone'] ?? '—'}'),
        Text('Society: ${record['societyName'] ?? '—'}'),
        Text('Flat: ${_place(record)}'),
        Text('City: ${record['societyCity'] ?? '—'}'),
        const SizedBox(height: 16),
        const Text('Photo', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        const SizedBox(height: 8),
        if (url == null || url.isEmpty)
          const Text('No photo uploaded', style: TextStyle(color: Color(0xFF6A7774)))
        else
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: InteractiveViewer(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return const SizedBox(
                    height: 220,
                    child: Center(child: CircularProgressIndicator()),
                  );
                },
                errorBuilder: (context, error, stack) => const SizedBox(
                  height: 120,
                  child: Center(child: Text('Could not load the photo')),
                ),
              ),
            ),
          ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            key: const Key('admin-address-proof-ok'),
            onPressed: _acting || status == 'OK' ? null : () => _mark('OK'),
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0E5A47)),
            child: const Text('Looks fine'),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: OutlinedButton(
            key: const Key('admin-address-proof-follow-up'),
            onPressed: _acting || status == 'FOLLOW_UP' ? null : () => _mark('FOLLOW_UP'),
            child: const Text('Needs follow-up'),
          ),
        ),
      ],
    );
  }
}
