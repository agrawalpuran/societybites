import 'package:flutter/material.dart';

import '../../models/seller_fssai.dart';
import '../../services/api_service.dart';
import '../../web/web_page_frame.dart';

class AdminFssaiAssistanceDetailScreen extends StatefulWidget {
  const AdminFssaiAssistanceDetailScreen({
    super.key,
    required this.assistanceId,
  });

  final String assistanceId;

  @override
  State<AdminFssaiAssistanceDetailScreen> createState() =>
      _AdminFssaiAssistanceDetailScreenState();
}

class _AdminFssaiAssistanceDetailScreenState
    extends State<AdminFssaiAssistanceDetailScreen> {
  Map<String, dynamic>? _detail;
  bool _loading = true;
  bool _updating = false;

  static const _statuses = [
    'NEW',
    'CONTACTED',
    'IN_PROGRESS',
    'COMPLETED',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final detail =
          await ApiService.getAdminFssaiAssistanceDetail(widget.assistanceId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.userFacingError(e))),
      );
    }
  }

  Future<void> _setStatus(String status) async {
    if (_detail == null || _updating) return;
    if (_detail!['status']?.toString() == status) return;
    setState(() => _updating = true);
    try {
      final updated = await ApiService.updateAdminFssaiAssistance(
        widget.assistanceId,
        status: status,
      );
      if (!mounted) return;
      setState(() {
        _detail = updated;
        _updating = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Assistance status updated')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _updating = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.userFacingError(e))),
      );
    }
  }

  static String? _formatDateTime(dynamic raw) {
    if (raw == null) return null;
    final dt = DateTime.tryParse(raw.toString());
    if (dt == null) return raw.toString();
    final local = dt.toLocal();
    final d = local.day.toString().padLeft(2, '0');
    final m = local.month.toString().padLeft(2, '0');
    return '$d/$m/${local.year} · ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'NEW':
        return 'New';
      case 'CONTACTED':
        return 'Contacted';
      case 'IN_PROGRESS':
        return 'In progress';
      case 'COMPLETED':
        return 'Completed';
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    return centerOnWeb(
      context,
      Scaffold(
        backgroundColor: const Color(0xFFF8FAF9),
        appBar: AppBar(
          title: const Text('FSSAI assistance'),
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF101617),
          elevation: 0,
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _detail == null
                ? const Center(child: Text('Could not load assistance request'))
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      _StatusBanner(
                        status: _detail!['status']?.toString() ?? 'NEW',
                        label: _statusLabel(
                          _detail!['status']?.toString() ?? 'NEW',
                        ),
                      ),
                      const SizedBox(height: 20),
                      _Section(
                        title: 'Seller',
                        children: [
                          _row('Name', _detail!['sellerName']?.toString()),
                          _row('Phone', _detail!['phone']?.toString()),
                          _row('Role', _detail!['role']?.toString()),
                          _row('Society', _detail!['societyName']?.toString()),
                          _row('Flat', _detail!['flatNumber']?.toString()),
                          _row('City', _detail!['societyCity']?.toString()),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _Section(
                        title: 'FSSAI (seller record)',
                        children: [
                          _row(
                            'Submission status',
                            SellerFssaiRegistration.statusLabels[
                                    _detail!['fssaiStatus']?.toString()] ??
                                _detail!['fssaiStatus']?.toString(),
                          ),
                          _row(
                            'Licence number',
                            _detail!['fssaiRegistrationNumber']?.toString(),
                          ),
                          _row(
                            'Registered name',
                            _detail!['fssaiRegisteredName']?.toString(),
                          ),
                          if (_detail!['detailsDeferred'] == true)
                            _row('Note', 'Details were deferred earlier'),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _Section(
                        title: 'Request',
                        children: [
                          _row(
                            'Requested',
                            _formatDateTime(_detail!['requestedAt']),
                          ),
                          _row(
                            'Last updated',
                            _formatDateTime(_detail!['updatedAt']),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Update status',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _statuses.map((status) {
                          final selected =
                              _detail!['status']?.toString() == status;
                          return ChoiceChip(
                            label: Text(_statusLabel(status)),
                            selected: selected,
                            onSelected: _updating
                                ? null
                                : (_) => _setStatus(status),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Audit trail',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      ..._auditEntries(),
                    ],
                  ),
      ),
      maxWidth: 720,
    );
  }

  List<Widget> _auditEntries() {
    final trail = _detail!['auditTrail'];
    if (trail is! List || trail.isEmpty) {
      return [
        const Text(
          'No events yet.',
          style: TextStyle(color: Color(0xFF6A7774)),
        ),
      ];
    }
    return trail.map((event) {
      final map = Map<String, dynamic>.from(event as Map);
      final at = _formatDateTime(map['at']) ?? '—';
      final label = map['label']?.toString() ?? 'Event';
      final actor = map['actorName']?.toString();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Icon(
                Icons.circle,
                size: 10,
                color: Color(0xFF0E5A47),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    at,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF8A9491),
                    ),
                  ),
                  if (actor != null && actor.isNotEmpty)
                    Text(
                      actor,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF6A7774),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  Widget _row(String label, String? value) {
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
              style: const TextStyle(fontWeight: FontWeight.w600),
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
    Color bg = const Color(0xFFF0F2F1);
    Color fg = const Color(0xFF6A7774);
    if (status == 'NEW') {
      bg = const Color(0xFFE8F0FF);
      fg = const Color(0xFF1A4FA3);
    } else if (status == 'COMPLETED') {
      bg = const Color(0xFFE8F5EE);
      fg = const Color(0xFF0E5A47);
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        'Assistance: $label',
        style: TextStyle(fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}
