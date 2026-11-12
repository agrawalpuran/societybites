import 'package:flutter/material.dart';

import '../services/api_service.dart';

/// PAN plus one settlement account. Cashfree accepts a bank account or a UPI ID, not both.
class SellerPayoutScreen extends StatefulWidget {
  const SellerPayoutScreen({super.key});

  @override
  State<SellerPayoutScreen> createState() => _SellerPayoutScreenState();
}

class _SellerPayoutScreenState extends State<SellerPayoutScreen> {
  final _pan = TextEditingController();
  final _account = TextEditingController();
  final _ifsc = TextEditingController();
  final _holder = TextEditingController();
  String _mode = 'upi';
  String? _upiId;
  String? _vendorStatus;
  String? _vendorError;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pan.dispose();
    _account.dispose();
    _ifsc.dispose();
    _holder.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profile = await ApiService.getSellerPayoutProfile();
      if (!mounted) return;
      setState(() {
        _pan.text = profile['pan']?.toString() ?? '';
        _mode = profile['settlementMode']?.toString() ?? 'upi';
        _account.text = profile['accountNumber']?.toString() ?? '';
        _ifsc.text = profile['ifsc']?.toString() ?? '';
        _holder.text = profile['accountHolder']?.toString() ?? '';
        _upiId = profile['upiId']?.toString();
        _vendorStatus = profile['vendorStatus']?.toString();
        _vendorError = profile['vendorError']?.toString();
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

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await ApiService.saveSellerPayoutProfile({
        'pan': _pan.text.trim(),
        'settlementMode': _mode,
        'accountNumber': _account.text.trim(),
        'ifsc': _ifsc.text.trim(),
        'accountHolder': _holder.text.trim(),
      });
      if (!mounted) return;
      setState(() {
        _vendorStatus = saved['vendorStatus']?.toString();
        _vendorError = saved['vendorError']?.toString();
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payout details saved')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
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
        title: const Text('Payout account'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Text(
                  'Cashfree pays this account after a buyer pays. Use either your UPI ID or a bank account.',
                  style: TextStyle(color: Color(0xFF6A7774), height: 1.4),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _pan,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'PAN'),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'upi', label: Text('UPI')),
                    ButtonSegment(value: 'bank', label: Text('Bank')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (value) {
                    setState(() => _mode = value.first);
                  },
                ),
                const SizedBox(height: 12),
                if (_mode == 'upi')
                  Text(
                    _upiId == null || _upiId!.isEmpty
                        ? 'Add a UPI ID in seller settings first.'
                        : 'Settlement UPI: $_upiId',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  )
                else ...[
                  TextField(
                    controller: _holder,
                    decoration: const InputDecoration(
                      labelText: 'Account holder name',
                    ),
                  ),
                  TextField(
                    controller: _account,
                    decoration: const InputDecoration(labelText: 'Account number'),
                    keyboardType: TextInputType.number,
                  ),
                  TextField(
                    controller: _ifsc,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'IFSC'),
                  ),
                ],
                if (_vendorStatus != null) ...[
                  const SizedBox(height: 12),
                  Text('Cashfree status: $_vendorStatus'),
                ],
                if (_vendorError != null && _vendorError!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    _vendorError!,
                    style: const TextStyle(color: Color(0xFFD94F4F)),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: Color(0xFFD94F4F))),
                ],
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0E5A47),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text(_saving ? 'Saving…' : 'Save'),
                ),
              ],
            ),
    );
  }
}
