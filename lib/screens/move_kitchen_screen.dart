import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../utils/picked_image.dart';
import '../web/web_page_frame.dart';
import '../widgets/document_image_upload_section.dart';

class MoveKitchenScreen extends StatefulWidget {
  const MoveKitchenScreen({super.key});

  @override
  State<MoveKitchenScreen> createState() => _MoveKitchenScreenState();
}

class _MoveKitchenScreenState extends State<MoveKitchenScreen> {
  final _searchController = TextEditingController();
  final _blockController = TextEditingController();
  final _flatController = TextEditingController();
  final _fssaiNumberController = TextEditingController();
  final _fssaiNameController = TextEditingController();
  DateTime? _licenceExpiry;
  Timer? _debounce;

  bool _loading = true;
  bool _saving = false;
  String? _error;
  Map<String, dynamic>? _current;
  Map<String, dynamic>? _pending;
  bool _fssaiRequired = false;
  Map<String, dynamic>? _society;
  List<Map<String, dynamic>> _results = [];
  bool _searching = false;
  int _searchSeq = 0;
  Uint8List? _proofBytes;
  String _proofMime = 'image/jpeg';
  Uint8List? _fssaiBytes;
  String _fssaiMime = 'image/jpeg';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    _blockController.dispose();
    _flatController.dispose();
    _fssaiNumberController.dispose();
    _fssaiNameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ApiService.getMyKitchenMove();
      if (!mounted) return;
      final move = data['move'];
      setState(() {
        _current = data['currentSociety'] is Map
            ? Map<String, dynamic>.from(data['currentSociety'] as Map)
            : null;
        _pending = move is Map ? Map<String, dynamic>.from(move) : null;
        _fssaiRequired = data['fssaiSellingRequirement'] == true;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ApiService.userFacingError(error);
      });
    }
  }

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
      final results = await ApiService.searchSocieties(query);
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

  Future<void> _pickProof(ImageSource source) async {
    final image = await pickDocumentImageFromSource(context, source: source);
    if (image == null || !mounted) return;
    setState(() {
      _proofBytes = image.bytes;
      _proofMime = image.mimeType;
    });
  }

  Future<void> _pickFssai(ImageSource source) async {
    final image = await pickDocumentImageFromSource(context, source: source);
    if (image == null || !mounted) return;
    setState(() {
      _fssaiBytes = image.bytes;
      _fssaiMime = image.mimeType;
    });
  }

  bool get _fssaiStarted =>
      _fssaiNumberController.text.trim().isNotEmpty ||
      _fssaiNameController.text.trim().isNotEmpty ||
      _licenceExpiry != null ||
      (_fssaiBytes != null && _fssaiBytes!.isNotEmpty);

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _licenceExpiry ?? now.add(const Duration(days: 365)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 20),
      helpText: 'Licence expiry date',
    );
    if (picked == null || !mounted) return;
    setState(() => _licenceExpiry = picked);
  }

  String _formatExpiry(DateTime date) {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    return '$d/$m/${date.year}';
  }

  String _expiryApiValue(DateTime date) {
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<void> _submit() async {
    final society = _society;
    if (society == null || _proofBytes == null || _proofBytes!.isEmpty) {
      setState(() => _error = 'Choose the new society and add an address photo');
      return;
    }
    final block = _blockController.text.trim();
    final flat = _flatController.text.trim();
    if ((block.isEmpty) != (flat.isEmpty)) {
      setState(() => _error = 'Enter both block and flat, or leave both empty');
      return;
    }
    Map<String, dynamic>? fssai;
    if (_fssaiStarted) {
      if (_fssaiNumberController.text.trim().isEmpty ||
          _fssaiNameController.text.trim().isEmpty ||
          _licenceExpiry == null ||
          _fssaiBytes == null) {
        setState(() {
          _error = 'Add the full FSSAI — number, name, expiry, and the licence photo';
        });
        return;
      }
      fssai = {
        'registrationNumber': _fssaiNumberController.text.trim(),
        'registeredName': _fssaiNameController.text.trim(),
        'licenceExpiry': _expiryApiValue(_licenceExpiry!),
        'imageBase64': base64Encode(_fssaiBytes!),
        'mimeType': _fssaiMime,
      };
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final proofUrl = await ApiService.uploadListingImage(
        bytes: _proofBytes!,
        mimeType: _proofMime,
        purpose: 'address-proof',
      );
      final societyId = society['id']?.toString();
      final placeId = society['placeId']?.toString();
      await ApiService.submitKitchenMove(
        societyId: societyId != null && societyId.isNotEmpty ? societyId : null,
        googlePlaceId: societyId == null || societyId.isEmpty ? placeId : null,
        block: block,
        flatNumber: flat,
        addressProofUrl: proofUrl,
        fssai: fssai,
      );
      if (!mounted) return;
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = ApiService.userFacingError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancel() async {
    setState(() => _saving = true);
    try {
      await ApiService.cancelMyKitchenMove();
      if (!mounted) return;
      await _load();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = ApiService.userFacingError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return centerOnWeb(
      context,
      Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E5A47),
        foregroundColor: Colors.white,
        title: const Text('Move kitchen'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
                children: [
                  Text(
                    _current == null
                        ? 'Your kitchen stays where it is until an admin approves the move.'
                        : 'Kitchen today: ${_current!['name'] ?? 'your society'}. It stays here until an admin approves the move.',
                    style: const TextStyle(color: Color(0xFF6A7774), height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _fssaiRequired
                        ? 'FSSAI is required, so the move is applied only after the licence for the new society is approved.'
                        : 'FSSAI is not required yet. You can ask to move with the address photo. A new licence can be reviewed later.',
                    style: const TextStyle(color: Color(0xFF6A7774), height: 1.4),
                  ),
                  if (_pending != null) ...[
                    const SizedBox(height: 20),
                    _PendingCard(move: _pending!, onCancel: _saving ? null : _cancel),
                  ] else ...[
                    const SizedBox(height: 20),
                    const Text(
                      'New society',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    if (_society == null) ...[
                      TextField(
                        controller: _searchController,
                        decoration: _fieldDecoration('Search the society'),
                        onChanged: (value) {
                          _debounce?.cancel();
                          _debounce = Timer(const Duration(milliseconds: 350), () {
                            _search(value);
                          });
                        },
                      ),
                      if (_searching)
                        const Padding(
                          padding: EdgeInsets.all(12),
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
                          title: Text(result['name']?.toString() ?? 'Society'),
                          subtitle: Text(result['city']?.toString() ?? ''),
                          onTap: () => setState(() {
                            _society = result;
                            _results = [];
                          }),
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
                                _society!['name']?.toString() ?? 'Society',
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
                      const SizedBox(height: 12),
                      TextField(
                        controller: _blockController,
                        decoration: _fieldDecoration('Block (optional)'),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _flatController,
                        decoration: _fieldDecoration('Flat (optional)'),
                      ),
                    ],
                    const SizedBox(height: 20),
                    DocumentImageUploadSection(
                      title: 'Address photo',
                      subtitle: 'A photo of the new kitchen address.',
                      bytes: _proofBytes,
                      onPickFromSource: _pickProof,
                      onRemove: () => setState(() => _proofBytes = null),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'FSSAI for the new kitchen',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Optional for now. If you add one, include the number, name, expiry, and licence photo.',
                      style: TextStyle(color: Color(0xFF6A7774), fontSize: 13, height: 1.35),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _fssaiNumberController,
                      decoration: _fieldDecoration('14-digit licence number'),
                      keyboardType: TextInputType.number,
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _fssaiNameController,
                      decoration: _fieldDecoration('Name on the licence'),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: _pickExpiryDate,
                      borderRadius: BorderRadius.circular(14),
                      child: InputDecorator(
                        decoration: _fieldDecoration('Expiry date').copyWith(
                          suffixIcon: const Icon(
                            Icons.calendar_today_outlined,
                            color: Color(0xFF0E5A47),
                            size: 20,
                          ),
                        ),
                        child: Text(
                          _licenceExpiry == null
                              ? 'Set expiry date'
                              : _formatExpiry(_licenceExpiry!),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: _licenceExpiry == null
                                ? const Color(0xFFBCC4C1)
                                : const Color(0xFF101617),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DocumentImageUploadSection(
                      title: 'Licence photo',
                      subtitle: 'The FSSAI certificate for this address.',
                      sheetTitle: 'FSSAI licence',
                      bytes: _fssaiBytes,
                      onPickFromSource: _pickFssai,
                      onRemove: () => setState(() => _fssaiBytes = null),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _saving ? null : _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0E5A47),
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: const Color(0xFFB5C4BF),
                          shape: const StadiumBorder(),
                          elevation: 0,
                        ),
                        child: Text(
                          _saving ? 'Sending…' : 'Request move',
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                      ),
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
                ],
              ),
      ),
      maxWidth: 480,
    );
  }
}

class _PendingCard extends StatelessWidget {
  const _PendingCard({required this.move, required this.onCancel});

  final Map<String, dynamic> move;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Waiting for admin',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            'Requested move to ${move['toSocietyName'] ?? 'the new society'}. '
            'Buyers still see this kitchen at the current society.',
            style: const TextStyle(height: 1.35),
          ),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: onCancel, child: const Text('Cancel request')),
        ],
      ),
    );
  }
}

InputDecoration _fieldDecoration(String hint) {
  return InputDecoration(
    hintText: hint,
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
