import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/seller_fssai.dart';
import '../services/api_service.dart';
import '../utils/picked_image.dart';
import '../web/web_page_frame.dart';
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
  final _nameController = TextEditingController();
  DateTime? _licenceExpiry;
  Uint8List? _documentBytes;
  String _documentMime = 'image/jpeg';
  String? _storageReference;
  bool _submitting = false;
  bool _noDetailsNow = false;

  bool get _fssaiRequired => _fssai?.requirementEnabled == true;

  bool get _showNoDetailsCheckbox =>
      !_fssaiRequired &&
      (_fssai?.status == 'NOT_SUBMITTED' || _fssai?.status == null);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _numberController.dispose();
    _nameController.dispose();
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
      _nameController.text = fssai.registeredName ?? '';
      _licenceExpiry = fssai.licenceExpiry;
      _noDetailsNow = fssai.detailsDeferred && fssai.requirementEnabled != true;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ApiService.userFacingError(e);
        _loading = false;
      });
    }
  }

  Future<void> _pickFromSource(ImageSource source) async {
    final picked = await pickDocumentImageFromSource(context, source: source);
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

  Future<void> _pickExpiryDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _licenceExpiry ?? now.add(const Duration(days: 365)),
      firstDate: now,
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

  InputDecoration _fieldDecoration({required Widget label}) {
    return InputDecoration(
      label: label,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  Widget _fieldLabel(String text, {required bool required}) {
    if (!required) {
      return Text(text, style: const TextStyle(color: Color(0xFF6A7774)));
    }
    return Text.rich(
      TextSpan(
        text: text,
        style: const TextStyle(color: Color(0xFF6A7774)),
        children: const [
          TextSpan(
            text: ' *',
            style: TextStyle(color: Color(0xFFC62828), fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitForm({required bool fieldsRequired}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          fieldsRequired
              ? 'Fields marked with * are required. Your submission will be reviewed before you can receive orders.'
              : 'Add whatever FSSAI details you have today. You can save partial information or come back later.',
          style: const TextStyle(color: Color(0xFF6A7774)),
        ),
        if (_showNoDetailsCheckbox) ...[
          const SizedBox(height: 12),
          Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            child: CheckboxListTile(
              value: _noDetailsNow,
              onChanged: _submitting
                  ? null
                  : (value) => setState(() => _noDetailsNow = value == true),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              title: const Text(
                'I do not have these details now',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF101617),
                ),
              ),
              subtitle: const Text(
                'You can still finish seller setup and add FSSAI later.',
                style: TextStyle(color: Color(0xFF6A7774), height: 1.35),
              ),
              activeColor: const Color(0xFF0E5A47),
            ),
          ),
        ],
        if (!_noDetailsNow) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _numberController,
            keyboardType: TextInputType.number,
            maxLength: 14,
            decoration: _fieldDecoration(
              label: _fieldLabel(
                'FSSAI registration / licence number',
                required: fieldsRequired,
              ),
            ).copyWith(counterText: ''),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: _fieldDecoration(
              label: _fieldLabel(
                'Registered name (as on licence)',
                required: fieldsRequired,
              ),
            ),
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickExpiryDate,
            borderRadius: BorderRadius.circular(14),
            child: InputDecorator(
              decoration: _fieldDecoration(
                label: _fieldLabel(
                  'Licence expiry date',
                  required: fieldsRequired,
                ),
              ),
              child: Text(
                _licenceExpiry == null
                    ? 'Select date'
                    : _formatExpiry(_licenceExpiry!),
                style: TextStyle(
                  fontSize: 16,
                  color: _licenceExpiry == null
                      ? const Color(0xFF8A9491)
                      : const Color(0xFF101617),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          DocumentImageUploadSection(
            title: fieldsRequired ? 'Document *' : 'Document',
            subtitle: 'Upload a clear photo of your FSSAI licence.',
            bytes: _documentBytes,
            onPickFromSource: _pickFromSource,
            onRemove: _removeDocument,
            sheetTitle: 'FSSAI document',
          ),
        ],
        const SizedBox(height: 16),
        if (_noDetailsNow && _showNoDetailsCheckbox)
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _submitting ? null : _continueWithoutDetails,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0E5A47),
              ),
              child: const Text('Continue'),
            ),
          )
        else ...[
          if (!fieldsRequired) ...[
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: _submitting ? null : _saveDraft,
                child: const Text('Save details'),
              ),
            ),
            const SizedBox(height: 10),
          ],
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
      ],
    );
  }

  bool _hasAnySubmitInput(SellerFssaiRegistration? fssai) {
    return _numberController.text.trim().isNotEmpty ||
        _nameController.text.trim().isNotEmpty ||
        _licenceExpiry != null ||
        (_documentBytes != null && _documentBytes!.isNotEmpty) ||
        (fssai?.hasDocument ?? false);
  }

  Future<void> _submitForReview() async {
    final number = _numberController.text.trim();
    final name = _nameController.text.trim();
    final fssai = _fssai;
    if (!_fssaiRequired && !_hasAnySubmitInput(fssai)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter complete FSSAI details to submit for review, save partial details, or check '
            '"I do not have these details now" to continue.',
          ),
        ),
      );
      return;
    }
    if (number.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your FSSAI registration number')),
      );
      return;
    }
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the registered name on your licence')),
      );
      return;
    }
    if (_licenceExpiry == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select your FSSAI licence expiry date')),
      );
      return;
    }
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
        registeredName: name,
        licenceExpiry: _expiryApiValue(_licenceExpiry!),
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

  Future<void> _saveDraft() async {
    final fssai = _fssai;
    if (!_hasAnySubmitInput(fssai)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter at least one FSSAI detail to save, or check '
            '"I do not have these details now" to continue.',
          ),
        ),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      if (_documentBytes != null) {
        _storageReference = await ApiService.uploadFssaiDocument(
          bytes: _documentBytes!,
          mimeType: _documentMime,
        );
        setState(() {
          _documentBytes = null;
        });
      }
      final updated = await ApiService.saveFssaiDraft(
        registrationNumber: _numberController.text.trim(),
        registeredName: _nameController.text.trim(),
        licenceExpiry: _licenceExpiry == null
            ? ''
            : _expiryApiValue(_licenceExpiry!),
      );
      if (!mounted) return;
      setState(() {
        _fssai = updated;
        _noDetailsNow = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('FSSAI details saved')),
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

  Future<void> _continueWithoutDetails() async {
    setState(() => _submitting = true);
    try {
      await ApiService.deferFssaiDetails();
      if (!mounted) return;
      Navigator.of(context).pop();
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

  static const _formMaxWidth = 600.0;

  @override
  Widget build(BuildContext context) {
    return centerOnWeb(
      context,
      Scaffold(
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
        body: SafeArea(
          child: _loading
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
                )
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final hPad = constraints.maxWidth > 400 ? 20.0 : 16.0;
                        return ListView(
                          keyboardDismissBehavior:
                              ScrollViewKeyboardDismissBehavior.onDrag,
                          padding: EdgeInsets.fromLTRB(hPad, 16, hPad, 28),
                          children: [
                    if (_fssai != null && !_fssai!.canSellDespiteFssai) ...[
                      _blockedBanner(),
                      const SizedBox(height: 16),
                    ],
                    _statusCard(),
                    const SizedBox(height: 20),
                    if (_fssai?.status == 'NOT_SUBMITTED' ||
                        _fssai?.status == 'REJECTED')
                      _buildSubmitForm(fieldsRequired: _fssaiRequired),
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
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: _requestAssistance,
                          child: const Text('Yes, I need help'),
                        ),
                      ),
                          ],
                        );
                      },
                    ),
        ),
      ),
      maxWidth: _formMaxWidth,
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
          if (fssai.registeredName != null) ...[
            const SizedBox(height: 4),
            Text('Name: ${fssai.registeredName}'),
          ],
          if (fssai.licenceExpiry != null) ...[
            const SizedBox(height: 4),
            Text('Expires: ${_formatExpiry(fssai.licenceExpiry!)}'),
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
