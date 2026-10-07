import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/seller_fssai.dart';
import '../services/api_service.dart';
import '../widgets/document_image_upload_section.dart';

class SellerFssaiScreen extends StatefulWidget {
  const SellerFssaiScreen({super.key});

  @override
  State<SellerFssaiScreen> createState() => _SellerFssaiScreenState();
}

class _SellerFssaiScreenState extends State<SellerFssaiScreen> {
  SellerFssaiRegistration? _fssai;
  bool _loading = true;
  String? _error;
  final _numberController = TextEditingController();
  Uint8List? _documentBytes;
  String _documentMime = 'image/jpeg';
  String? _storageReference;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _numberController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fssai = await ApiService.getMyFssai();
      if (!mounted) return;
      _fssai = fssai;
      _numberController.text = fssai.registrationNumber ?? '';
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiService.userFacingError(e);
        _loading = false;
      });
    }
  }

  Future<void> _pickDocument() async {
    final picked = await pickDocumentImage(context, sheetTitle: 'FSSAI document');
    if (picked == null || !mounted) return;
    setState(() {
      _documentBytes = picked.bytes;
      _documentMime = picked.mimeType;
      _storageReference = null;
    });
  }

  void _removeDocument() {
    setState(() {
      _documentBytes = null;
      _storageReference = null;
    });
  }

  Future<void> _submitForReview() async {
    final number = _numberController.text.trim();
    if (number.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your FSSAI registration number')),
      );
      return;
    }
    final fssai = _fssai;
    if (_documentBytes == null && !(fssai?.hasDocument ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a photo of your FSSAI document')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      var storageRef = _storageReference;
      if (_documentBytes != null) {
        storageRef = await ApiService.uploadFssaiDocument(
          bytes: _documentBytes!,
          mimeType: _documentMime,
        );
      }
      final updated = await ApiService.submitFssaiForReview(
        registrationNumber: number,
        storageReference: storageRef,
      );
      if (!mounted) return;
      setState(() {
        _fssai = updated;
        _documentBytes = null;
        _storageReference = storageRef;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Submitted for review')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.userFacingError(e))),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _requestAssistance() async {
    try {
      await ApiService.requestFssaiAssistance();
      if (!mounted) return;
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('FSSAI assistance requested')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.userFacingError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF101617),
        title: const Text(
          'FSSAI Registration',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF0E5A47)))
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
                  children: [
                    if (_fssai != null && !_fssai!.canSellDespiteFssai) ...[
                      _blockedBanner(),
                      const SizedBox(height: 16),
                    ],
                    _statusCard(),
                    const SizedBox(height: 20),
                    if (_fssai?.status == 'NOT_SUBMITTED' ||
                        _fssai?.status == 'REJECTED') ...[
                      const Text(
                        'Add your FSSAI registration/license details.',
                        style: TextStyle(color: Color(0xFF6A7774)),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _numberController,
                        keyboardType: TextInputType.number,
                        maxLength: 14,
                        decoration: InputDecoration(
                          labelText: 'FSSAI Registration/License Number',
                          counterText: '',
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      DocumentImageUploadSection(
                        title: 'Document',
                        subtitle: 'Upload a clear photo of your FSSAI licence.',
                        bytes: _documentBytes,
                        onPick: _pickDocument,
                        onRemove: _removeDocument,
                        sheetTitle: 'FSSAI document',
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: FilledButton(
                          onPressed: _submitting ? null : _submitForReview,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0E5A47),
                          ),
                          child: Text(
                            _fssai?.status == 'REJECTED'
                                ? 'Submit New Document'
                                : 'Submit for Review',
                          ),
                        ),
                      ),
                    ],
                    if (_fssai?.status == 'UNDER_REVIEW') ...[
                      const Text(
                        'Your FSSAI registration details have been submitted and are currently being reviewed.',
                        style: TextStyle(
                          height: 1.45,
                          color: Color(0xFF6A7774),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Text(
                      'Need help getting your FSSAI registration?',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    if (_fssai?.assistanceRequested == true)
                      const Text(
                        'FSSAI assistance requested',
                        style: TextStyle(color: Color(0xFF0E5A47), fontWeight: FontWeight.w600),
                      )
                    else
                      OutlinedButton(
                        onPressed: _requestAssistance,
                        child: const Text('Yes, I need help'),
                      ),
                  ],
                ),
    );
  }

  Widget _statusCard() {
    final fssai = _fssai!;
    return Container(
      width: double.infinity,
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
            'FSSAI Registration',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'Status: ${fssai.statusLabel}',
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF0E5A47),
            ),
          ),
          if (fssai.registrationNumber != null) ...[
            const SizedBox(height: 6),
            Text('Licence: ${fssai.registrationNumber}'),
          ],
          if (fssai.status == 'REJECTED' && fssai.rejectionReason != null) ...[
            const SizedBox(height: 10),
            const Text(
              'Your submission could not be approved.',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            Text('Reason: ${fssai.rejectionReason}'),
          ],
        ],
      ),
    );
  }

  Widget _blockedBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFF0D2A8)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'FSSAI registration required',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
          SizedBox(height: 6),
          Text(
            'SocietyEats currently requires approved FSSAI registration to sell food. '
            'Your listings are saved, but you cannot receive new orders until your FSSAI registration is approved.',
            style: TextStyle(height: 1.4, color: Color(0xFF5C4A32)),
          ),
        ],
      ),
    );
  }
}
