import 'package:flutter/material.dart';

import '../../models/seller_fssai.dart';
import '../../services/api_service.dart';
import '../../web/web_page_frame.dart';

/// Admin review of one seller FSSAI submission (document + approve / reject).
class AdminFssaiSubmissionDetailScreen extends StatefulWidget {
  const AdminFssaiSubmissionDetailScreen({
    super.key,
    required this.submission,
  });

  final Map<String, dynamic> submission;

  @override
  State<AdminFssaiSubmissionDetailScreen> createState() =>
      _AdminFssaiSubmissionDetailScreenState();
}

class _AdminFssaiSubmissionDetailScreenState
    extends State<AdminFssaiSubmissionDetailScreen> {
  String? _documentUrl;
  bool _loadingDoc = false;
  bool _acting = false;

  String get _sellerId => widget.submission['sellerId']?.toString() ?? '';
  String get _status =>
      widget.submission['status']?.toString() ?? 'NOT_SUBMITTED';

  @override
  void initState() {
    super.initState();
    if (widget.submission['hasDocument'] == true) {
      _loadDocument();
    }
  }

  Future<void> _loadDocument() async {
    setState(() => _loadingDoc = true);
    try {
      final url = await ApiService.getAdminFssaiDocumentUrl(_sellerId);
      if (!mounted) return;
      setState(() {
        _documentUrl = url;
        _loadingDoc = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadingDoc = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load document: $e')),
      );
    }
  }

  Future<void> _approve() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve FSSAI?'),
        content: Text(
          'Approve registration for ${widget.submission['name'] ?? 'this seller'}? '
          'They can receive orders if platform FSSAI requirement is on.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Approve'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _acting = true);
    try {
      await ApiService.approveAdminFssai(_sellerId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('FSSAI approved')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _acting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.userFacingError(e))),
      );
    }
  }

  Future<void> _reject() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject FSSAI'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Give a clear reason so the seller can fix and resubmit.',
              style: TextStyle(color: Color(0xFF6A7774), height: 1.35),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Rejection reason *',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(ctx, text);
            },
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty || !mounted) return;
    setState(() => _acting = true);
    try {
      await ApiService.rejectAdminFssai(_sellerId, rejectionReason: reason);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('FSSAI rejected')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _acting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.userFacingError(e))),
      );
    }
  }

  static String? _formatDate(dynamic raw) {
    if (raw == null) return null;
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return raw.toString();
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    return '$d/$m/${local.year}';
  }

  static String? _formatDateTime(dynamic raw) {
    if (raw == null) return null;
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return raw.toString();
    final local = dt.toLocal();
    return '${_formatDate(local)} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.submission;
    final statusLabel =
        SellerFssaiRegistration.statusLabels[_status] ?? _status;
    final canReview = _status == 'UNDER_REVIEW' && !_acting;

    return centerOnWeb(
      context,
      Scaffold(
        backgroundColor: const Color(0xFFF8FAF9),
        appBar: AppBar(
          title: const Text('FSSAI submission'),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF101617),
          elevation: 0,
        ),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _StatusBanner(status: _status, label: statusLabel),
            const SizedBox(height: 20),
            _Section(
              title: 'Seller',
              children: [
                _row('Name', s['name']?.toString()),
                _row('Phone', s['phone']?.toString()),
                _row('Role', s['role']?.toString()),
                _row('Society', s['societyName']?.toString()),
                _row('Flat', s['flatNumber']?.toString()),
                _row('City', s['societyCity']?.toString()),
              ],
            ),
            const SizedBox(height: 16),
            _Section(
              title: 'FSSAI registration',
              children: [
                _row('Registered name', s['registeredName']?.toString()),
                _row('Licence number', s['registrationNumber']?.toString()),
                _row('Expiry', _formatDate(s['licenceExpiry'])),
                _row('Submitted', _formatDateTime(s['submittedAt'])),
                _row('Reviewed', _formatDateTime(s['reviewedAt'])),
                if (s['detailsDeferred'] == true)
                  _row('Note', 'Seller deferred details (requirement was off)'),
                if (s['needsAssistance'] == true)
                  _row('Help requested', 'Yes'),
                if (_status == 'REJECTED' &&
                    s['rejectionReason'] != null &&
                    s['rejectionReason'].toString().isNotEmpty)
                  _row('Rejection reason', s['rejectionReason']?.toString(),
                      emphasize: true),
              ],
            ),
            const SizedBox(height: 16),
            const Text(
              'Licence document',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            const SizedBox(height: 8),
            if (s['hasDocument'] != true)
              const Text(
                'No document uploaded',
                style: TextStyle(color: Color(0xFF6A7774)),
              )
            else if (_loadingDoc)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_documentUrl != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: InteractiveViewer(
                  child: Image.network(
                    _documentUrl!,
                    fit: BoxFit.contain,
                    loadingBuilder: (ctx, child, progress) {
                      if (progress == null) return child;
                      return const SizedBox(
                        height: 200,
                        child: Center(child: CircularProgressIndicator()),
                      );
                    },
                  ),
                ),
              )
            else
              TextButton(
                onPressed: _loadDocument,
                child: const Text('Retry loading document'),
              ),
            if (canReview) ...[
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _approve,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0E5A47),
                  ),
                  child: const Text('Approve'),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: _reject,
                  child: const Text('Reject with reason'),
                ),
              ),
            ],
            if (_acting)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
      maxWidth: 720,
    );
  }

  Widget _row(String label, String? value, {bool emphasize = false}) {
    final display = (value == null || value.trim().isEmpty) ? '—' : value;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF6A7774),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              display,
              style: TextStyle(
                fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
                color: emphasize
                    ? const Color(0xFFC62828)
                    : const Color(0xFF101617),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.status, required this.label});

  final String status;
  final String label;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (status) {
      case 'UNDER_REVIEW':
        bg = const Color(0xFFFFF4E5);
        fg = const Color(0xFF8A5A00);
      case 'APPROVED':
        bg = const Color(0xFFE8F5EE);
        fg = const Color(0xFF0E5A47);
      case 'REJECTED':
        bg = const Color(0xFFFDECEC);
        fg = const Color(0xFFC62828);
      default:
        bg = const Color(0xFFF0F2F1);
        fg = const Color(0xFF6A7774);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Status: $label',
        style: TextStyle(fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}
