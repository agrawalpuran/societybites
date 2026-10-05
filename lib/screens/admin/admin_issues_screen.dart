import 'package:flutter/material.dart';

import '../../models/issue_report.dart';
import '../../services/api_service.dart';
import '../../widgets/screen_loading_note.dart';

class AdminIssuesScreen extends StatefulWidget {
  const AdminIssuesScreen({super.key});

  @override
  State<AdminIssuesScreen> createState() => _AdminIssuesScreenState();
}

class _AdminIssuesScreenState extends State<AdminIssuesScreen> {
  static const _filters = ['ALL', 'OPEN', 'UNDER_REVIEW', 'RESOLVED', 'CLOSED'];

  List<IssueReport> _issues = const [];
  String _filter = 'ALL';
  bool _loading = true;
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
      final issues = await ApiService.getAdminIssues(
        status: _filter == 'ALL' ? null : _filter,
      );
      if (!mounted) return;
      setState(() => _issues = issues);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = ApiService.userFacingError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            'Issues & Reports',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final filter in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(filter == 'ALL' ? 'All' : IssueReport.statuses[filter]!),
                    selected: _filter == filter,
                    onSelected: (_) {
                      setState(() => _filter = filter);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const ScreenLoadingNote(message: 'Loading issues…')
              : _error != null
                  ? Center(child: Text(_error!))
                  : _issues.isEmpty
                      ? const Center(child: Text('No reports'))
                      : RefreshIndicator(
                          color: const Color(0xFF0E5A47),
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _issues.length,
                            itemBuilder: (context, index) {
                              final issue = _issues[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                elevation: 0,
                                color: Colors.white,
                                child: ListTile(
                                  title: Text(
                                    '${issue.reference} · ${issue.categoryLabel}',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  subtitle: Text(
                                    '${issue.reporterName ?? 'Resident'} · ${issue.roleLabel}\n${issue.statusLabel} · ${formatIssueDate(issue.createdAt)}',
                                  ),
                                  isThreeLine: true,
                                  onTap: () async {
                                    await Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => AdminIssueDetailScreen(issueId: issue.id),
                                      ),
                                    );
                                    if (mounted) _load();
                                  },
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}

class AdminIssueDetailScreen extends StatefulWidget {
  const AdminIssueDetailScreen({super.key, required this.issueId});

  final String issueId;

  @override
  State<AdminIssueDetailScreen> createState() => _AdminIssueDetailScreenState();
}

class _AdminIssueDetailScreenState extends State<AdminIssueDetailScreen> {
  final _response = TextEditingController();
  IssueReport? _issue;
  String? _status;
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
    _response.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final issue = await ApiService.getAdminIssue(widget.issueId);
      if (!mounted) return;
      _response.text = issue.adminResponse ?? '';
      setState(() {
        _issue = issue;
        _status = issue.status;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = ApiService.userFacingError(error);
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    final issue = _issue;
    if (issue == null || _status == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await ApiService.updateAdminIssue(
        issue.id,
        status: _status,
        adminResponse: _response.text.trim(),
      );
      if (!mounted) return;
      setState(() => _issue = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Report updated')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = ApiService.userFacingError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final issue = _issue;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0E5A47),
        foregroundColor: Colors.white,
        title: Text(issue?.reference ?? 'Issue'),
      ),
      body: _loading
          ? const ScreenLoadingNote(message: 'Loading issue…')
          : issue == null
              ? Center(child: Text(_error ?? 'Report not found'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(issue.categoryLabel, style: const TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text('${issue.reporterName ?? 'Resident'} · ${issue.roleLabel}'),
                    const SizedBox(height: 8),
                    Text('Submitted ${formatIssueDate(issue.createdAt)}'),
                    const SizedBox(height: 16),
                    Text(issue.description),
                    if (issue.orderId != null) ...[
                      const SizedBox(height: 12),
                      Text('Order: ${issue.orderId}'),
                    ],
                    if (issue.listingId != null) ...[
                      const SizedBox(height: 8),
                      Text('Listing: ${issue.listingId}'),
                    ],
                    if (issue.sellerId != null) ...[
                      const SizedBox(height: 8),
                      Text('Seller: ${issue.sellerId}'),
                    ],
                    const SizedBox(height: 20),
                    DropdownButtonFormField<String>(
                      initialValue: _status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: [
                        for (final entry in IssueReport.statuses.entries)
                          DropdownMenuItem(value: entry.key, child: Text(entry.value)),
                      ],
                      onChanged: (value) => setState(() => _status = value),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _response,
                      minLines: 3,
                      maxLines: 6,
                      maxLength: 2000,
                      decoration: const InputDecoration(
                        labelText: 'Admin response',
                        hintText: 'Optional note for the person who reported this',
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 8),
                      Text(_error!, style: const TextStyle(color: Color(0xFFD94F4F))),
                    ],
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: _saving ? null : _save,
                      style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0E5A47)),
                      child: Text(_saving ? 'Saving...' : 'Save'),
                    ),
                  ],
                ),
    );
  }
}
