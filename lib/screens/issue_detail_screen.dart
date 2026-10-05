import 'package:flutter/material.dart';

import '../models/issue_report.dart';
import '../services/api_service.dart';
import '../web/web_page_frame.dart';
import '../widgets/screen_loading_note.dart';

class IssueDetailScreen extends StatefulWidget {
  const IssueDetailScreen({super.key, required this.issueId, this.initial});

  final String issueId;
  final IssueReport? initial;

  @override
  State<IssueDetailScreen> createState() => _IssueDetailScreenState();
}

class _IssueDetailScreenState extends State<IssueDetailScreen> {
  IssueReport? _issue;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _issue = widget.initial;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _issue == null;
      _error = null;
    });
    try {
      final issue = await ApiService.getIssue(widget.issueId);
      if (!mounted) return;
      setState(() => _issue = issue);
    } catch (error) {
      if (!mounted) return;
      if (_issue == null) setState(() => _error = ApiService.userFacingError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final issue = _issue;
    return panelOnWeb(
      context,
      Scaffold(
        backgroundColor: const Color(0xFFF8FAF9),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: const Color(0xFF101617),
          title: Text(
            issue?.reference ?? 'Report',
            style: const TextStyle(color: Color(0xFF101617), fontWeight: FontWeight.w700),
          ),
        ),
        body: _loading
            ? const ScreenLoadingNote(message: 'Loading report…')
            : _error != null
                ? Center(child: Text(_error!))
                : issue == null
                    ? const SizedBox.shrink()
                    : ListView(
                        padding: const EdgeInsets.all(20),
                        children: [
                          Text(
                            issue.reference,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0E5A47),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(issue.categoryLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 16),
                          Text(issue.description, style: const TextStyle(height: 1.4)),
                          if (issue.orderId != null) ...[
                            const SizedBox(height: 16),
                            Text('Order: ${issue.orderId}'),
                          ],
                          if (issue.listingId != null) ...[
                            const SizedBox(height: 8),
                            Text('Listing: ${issue.listingId}'),
                          ],
                          const SizedBox(height: 16),
                          Text(
                            'Submitted ${formatIssueDate(issue.createdAt)}',
                            style: const TextStyle(color: Color(0xFF6A7774)),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            issue.statusLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0E5A47),
                            ),
                          ),
                          if (issue.adminResponse != null) ...[
                            const SizedBox(height: 22),
                            const Text(
                              'SocietyEats',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              issue.adminResponse!,
                              style: const TextStyle(height: 1.4),
                            ),
                          ],
                        ],
                      ),
      ),
    );
  }
}
