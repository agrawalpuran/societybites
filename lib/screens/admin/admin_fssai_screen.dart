import 'package:flutter/material.dart';

import '../../models/seller_fssai.dart';
import '../../services/api_service.dart';
import '../../widgets/admin_loading_panel.dart';
import 'admin_fssai_assistance_detail_screen.dart';
import 'admin_fssai_submission_detail_screen.dart';

class AdminFssaiScreen extends StatefulWidget {
  const AdminFssaiScreen({super.key});

  @override
  State<AdminFssaiScreen> createState() => _AdminFssaiScreenState();
}

class _AdminFssaiScreenState extends State<AdminFssaiScreen> {
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _records = const [];
  List<Map<String, dynamic>> _assistance = const [];
  bool _loading = true;
  bool _requirementOn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.getAdminFssaiSummary(),
        ApiService.getAdminFssaiSubmissions(),
        ApiService.getAdminFssaiAssistance(),
      ]);
      if (!mounted) return;
      setState(() {
        _summary = results[0] as Map<String, dynamic>;
        _records = results[1] as List<Map<String, dynamic>>;
        _assistance = results[2] as List<Map<String, dynamic>>;
        _requirementOn = _summary!['requirementEnabled'] == true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load FSSAI admin: $e')),
      );
    }
  }

  Future<void> _toggleRequirement(bool value) async {
    try {
      final on = await ApiService.updateAdminFssaiRequirement(value);
      if (!mounted) return;
      setState(() => _requirementOn = on);
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update requirement: $e')),
      );
    }
  }

  Future<void> _openAssistance(Map<String, dynamic> row) async {
    final id = row['id']?.toString();
    if (id == null || id.isEmpty) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminFssaiAssistanceDetailScreen(assistanceId: id),
      ),
    );
    await _load();
  }

  Future<void> _openSubmission(Map<String, dynamic> row) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminFssaiSubmissionDetailScreen(submission: row),
      ),
    );
    if (changed == true) await _load();
  }

  String _submissionSubtitle(Map<String, dynamic> row) {
    final status = row['status']?.toString() ?? '';
    final society = row['societyName']?.toString() ?? '—';
    final phone = row['phone']?.toString();
    final reg = row['registrationNumber']?.toString();
    final parts = <String>[society];
    if (phone != null && phone.isNotEmpty) parts.add(phone);
    if (reg != null && reg.isNotEmpty) parts.add('Licence: $reg');
    if (status == 'NOT_SUBMITTED' && row['detailsDeferred'] == true) {
      parts.add('Deferred');
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const AdminLoadingPanel(message: 'Loading FSSAI…');
    }
    final submissions = _summary?['submissions'] as Map? ?? {};
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            title: const Text('FSSAI selling requirement'),
            subtitle: Text(_requirementOn ? 'ON' : 'OFF'),
            value: _requirementOn,
            onChanged: _toggleRequirement,
          ),
          Text(
            'Pending review: ${submissions['UNDER_REVIEW'] ?? 0} · '
            'Approved: ${submissions['APPROVED'] ?? 0} · '
            'Rejected: ${submissions['REJECTED'] ?? 0}',
          ),
          const SizedBox(height: 8),
          const Text(
            'Tap a row to view seller and licence details, open the document, '
            'and approve or reject.',
            style: TextStyle(fontSize: 13, color: Color(0xFF6A7774), height: 1.35),
          ),
          const SizedBox(height: 16),
          const Text('Submissions', style: TextStyle(fontWeight: FontWeight.w800)),
          for (final row in _records)
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: InkWell(
                onTap: () => _openSubmission(row),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row['name']?.toString() ?? 'Seller',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _submissionSubtitle(row),
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF6A7774),
                                height: 1.35,
                              ),
                            ),
                            if (row['registeredName'] != null &&
                                row['registeredName'].toString().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                'On licence: ${row['registeredName']}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      _StatusChip(status: row['status']?.toString() ?? ''),
                      const Icon(Icons.chevron_right, color: Color(0xFF8A9491)),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 16),
          const Text('FSSAI assistance', style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text(
            'Tap a request for seller details and the audit trail.',
            style: TextStyle(fontSize: 13, color: Color(0xFF6A7774), height: 1.35),
          ),
          for (final row in _assistance)
            Card(
              margin: const EdgeInsets.only(top: 8),
              child: InkWell(
                onTap: () => _openAssistance(row),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              row['sellerName']?.toString() ?? 'Seller',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${row['societyName'] ?? '—'} · ${row['phone'] ?? '—'}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF6A7774),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _AssistanceStatusChip(
                        status: row['status']?.toString() ?? 'NEW',
                      ),
                      const Icon(Icons.chevron_right, color: Color(0xFF8A9491)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AssistanceStatusChip extends StatelessWidget {
  const _AssistanceStatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    String label;
    switch (status) {
      case 'CONTACTED':
        label = 'Contacted';
      case 'IN_PROGRESS':
        label = 'In progress';
      case 'COMPLETED':
        label = 'Done';
      default:
        label = 'New';
    }
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F0FF),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1A4FA3),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final label = SellerFssaiRegistration.statusLabels[status] ?? status;
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
