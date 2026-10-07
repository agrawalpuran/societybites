import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../widgets/screen_loading_note.dart';

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

  Future<void> _openDocument(String sellerId) async {
    try {
      final url = await ApiService.getAdminFssaiDocumentUrl(sellerId);
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => Dialog(
          child: InteractiveViewer(
            child: Image.network(url, fit: BoxFit.contain),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open document: $e')),
      );
    }
  }

  Future<void> _reject(String sellerId) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject FSSAI'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Rejection reason'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.isEmpty) return;
    await ApiService.rejectAdminFssai(sellerId, rejectionReason: reason);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const ScreenLoadingNote(message: 'Loading FSSAI…');
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
          const SizedBox(height: 16),
          const Text('Submissions', style: TextStyle(fontWeight: FontWeight.w800)),
          for (final row in _records)
            Card(
              child: ListTile(
                title: Text(row['name']?.toString() ?? 'Seller'),
                subtitle: Text(
                  '${row['societyName'] ?? '—'} · ${row['status']} · ${row['registrationNumber'] ?? '—'}',
                ),
                trailing: row['status'] == 'UNDER_REVIEW'
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (row['hasDocument'] == true)
                            IconButton(
                              icon: const Icon(Icons.image_outlined),
                              onPressed: () =>
                                  _openDocument(row['sellerId'].toString()),
                            ),
                          TextButton(
                            onPressed: () =>
                                ApiService.approveAdminFssai(row['sellerId'].toString())
                                    .then((_) => _load()),
                            child: const Text('Approve'),
                          ),
                          TextButton(
                            onPressed: () => _reject(row['sellerId'].toString()),
                            child: const Text('Reject'),
                          ),
                        ],
                      )
                    : null,
              ),
            ),
          const SizedBox(height: 16),
          const Text('FSSAI assistance', style: TextStyle(fontWeight: FontWeight.w800)),
          for (final row in _assistance)
            ListTile(
              title: Text(row['sellerName']?.toString() ?? 'Seller'),
              subtitle: Text('${row['societyName'] ?? '—'} · ${row['status']}'),
              trailing: PopupMenuButton<String>(
                onSelected: (status) => ApiService.updateAdminFssaiAssistance(
                  row['id'].toString(),
                  status: status,
                ).then((_) => _load()),
                itemBuilder: (ctx) => const [
                  PopupMenuItem(value: 'NEW', child: Text('NEW')),
                  PopupMenuItem(value: 'CONTACTED', child: Text('CONTACTED')),
                  PopupMenuItem(value: 'IN_PROGRESS', child: Text('IN PROGRESS')),
                  PopupMenuItem(value: 'COMPLETED', child: Text('COMPLETED')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
