import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../web/web_page_frame.dart';

class AddBuyerAddressScreen extends StatefulWidget {
  const AddBuyerAddressScreen({
    super.key,
    this.searchSocieties,
    this.saveAddress,
  });

  final Future<List<Map<String, dynamic>>> Function(String query)?
      searchSocieties;
  final Future<Map<String, dynamic>> Function({
    required String label,
    String? societyId,
    String? googlePlaceId,
    String? block,
    String? flatNumber,
  })? saveAddress;

  @override
  State<AddBuyerAddressScreen> createState() => _AddBuyerAddressScreenState();
}

class _AddBuyerAddressScreenState extends State<AddBuyerAddressScreen> {
  final _labelController = TextEditingController();
  final _searchController = TextEditingController();
  final _blockController = TextEditingController();
  final _flatController = TextEditingController();
  Timer? _debounce;
  List<Map<String, dynamic>> _results = [];
  Map<String, dynamic>? _society;
  bool _searching = false;
  bool _saving = false;
  String? _error;
  int _searchSeq = 0;

  static const _suggestions = ['Home', 'Office', 'Other'];

  @override
  void dispose() {
    _debounce?.cancel();
    _labelController.dispose();
    _searchController.dispose();
    _blockController.dispose();
    _flatController.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _labelController.text.trim().isNotEmpty && _society != null && !_saving;

  Future<void> _search(String value) async {
    final query = value.trim();
    final seq = ++_searchSeq;
    if (query.length < 2) {
      setState(() {
        _results = [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final search = widget.searchSocieties ?? ApiService.searchSocieties;
      final results = await search(query);
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = results;
        _searching = false;
      });
    } catch (error) {
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = [];
        _searching = false;
        _error = ApiService.userFacingError(error);
      });
    }
  }

  Future<void> _save() async {
    if (!_canSave || _society == null) return;
    final block = _blockController.text.trim();
    final flat = _flatController.text.trim();
    if ((block.isEmpty) != (flat.isEmpty)) {
      setState(() {
        _error = 'Enter both block and flat, or leave both empty';
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final societyId = _society!['id']?.toString().trim();
      final placeId = _society!['placeId']?.toString().trim();
      final save = widget.saveAddress ?? ApiService.addBuyerAddress;
      await save(
        label: _labelController.text.trim(),
        societyId: (societyId != null && societyId.isNotEmpty) ? societyId : null,
        googlePlaceId: (placeId != null && placeId.isNotEmpty) ? placeId : null,
        block: block.isEmpty ? null : block,
        flatNumber: flat.isEmpty ? null : flat,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = ApiService.userFacingError(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final societyName = _society?['name']?.toString();
    return centerOnWeb(
      context,
      Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAF9),
        foregroundColor: const Color(0xFF101617),
        elevation: 0,
        title: const Text(
          'Add address',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          const Text(
            'Name',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            key: const Key('buyer-address-label'),
            controller: _labelController,
            textCapitalization: TextCapitalization.sentences,
            decoration: _fieldDecoration('Home'),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final suggestion in _suggestions)
                ActionChip(
                  label: Text(suggestion),
                  onPressed: () {
                    _labelController.text = suggestion;
                    setState(() {});
                  },
                ),
            ],
          ),
          const SizedBox(height: 20),
          const Text(
            'Society',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 8),
          if (_society == null) ...[
            TextField(
              key: const Key('buyer-address-society-search'),
              controller: _searchController,
              decoration: _fieldDecoration('Search your society'),
              onChanged: (value) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 350), () {
                  _search(value);
                });
              },
            ),
            if (_searching)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
            for (final result in _results)
              ListTile(
                key: Key('buyer-address-society-${result['id'] ?? result['placeId']}'),
                title: Text(result['name']?.toString() ?? 'Society'),
                subtitle: Text(
                  result['city']?.toString() ??
                      result['address']?.toString() ??
                      '',
                ),
                onTap: () {
                  setState(() {
                    _society = result;
                    _results = [];
                    _error = null;
                  });
                },
              ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFEAEFED)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      societyName ?? 'Society',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _society = null),
                    child: const Text('Change'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Flat and block are optional.',
              style: TextStyle(color: Color(0xFF6A7774), fontSize: 13),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('buyer-address-block'),
              controller: _blockController,
              decoration: _fieldDecoration('Block'),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('buyer-address-flat'),
              controller: _flatController,
              decoration: _fieldDecoration('Flat'),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(
                color: Color(0xFFD94F4F),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 20),
          const Text(
            'Saving adds the place to your list. It is used after you choose it.',
            style: TextStyle(color: Color(0xFF6A7774), fontSize: 13),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              key: const Key('buyer-address-save'),
              onPressed: _canSave ? _save : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _canSave
                    ? const Color(0xFF0E5A47)
                    : const Color(0xFFB5C4BF),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFB5C4BF),
                disabledForegroundColor: Colors.white,
                shape: const StadiumBorder(),
                elevation: 0,
              ),
              child: Text(
                _saving ? 'Saving…' : 'Save address',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    ),
    maxWidth: 480,
    );
  }
}

InputDecoration _fieldDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(
      color: Color(0xFFBCC4C1),
      fontSize: 15,
      fontWeight: FontWeight.w500,
    ),
    filled: true,
    fillColor: const Color(0xFFF5F7F6),
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE6EBE9)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFFE6EBE9)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: Color(0xFF0E5A47), width: 1.4),
    ),
  );
}
