import 'package:flutter/material.dart';

import '../models/issue_report.dart';
import '../services/api_service.dart';
import '../web/web_page_frame.dart';
import '../widgets/screen_loading_note.dart';
import 'issue_detail_screen.dart';

class MyReportsScreen extends StatefulWidget {
  const MyReportsScreen({super.key, this.loadReports});

  final Future<List<IssueReport>> Function()? loadReports;

  @override
  State<MyReportsScreen> createState() => _MyReportsScreenState();
}

class _MyReportsScreenState extends State<MyReportsScreen> {
  List<IssueReport> _reports = const [];
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
      final reports = widget.loadReports != null
          ? await widget.loadReports!()
          : await ApiService.getMyIssues();
      if (!mounted) return;
      setState(() => _reports = reports);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = ApiService.userFacingError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

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
            'My Reports',
            style: TextStyle(color: Color(0xFF101617), fontWeight: FontWeight.w700),
          ),
        ),
        body: _loading
            ? const ScreenLoadingNote(message: 'Loading your reports…')
            : _error != null
                ? _message(_error!, action: 'Try again', onTap: _load)
                : _reports.isEmpty
                    ? const IssueReportsEmptyState()
                    : RefreshIndicator(
                        color: const Color(0xFF0E5A47),
                        onRefresh: _load,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _reports.length,
                          itemBuilder: (context, index) {
                            final report = _reports[index];
                            return _ReportCard(
                              report: report,
                              onTap: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => IssueDetailScreen(issueId: report.id),
                                  ),
                                );
                                if (mounted) _load();
                              },
                            );
                          },
                        ),
                      ),
      ),
    );
  }

  Widget _message(String text, {required String action, required VoidCallback onTap}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(onPressed: onTap, child: Text(action)),
          ],
        ),
      ),
    );
  }
}

class IssueReportsEmptyState extends StatelessWidget {
  const IssueReportsEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 42, color: Color(0xFF8A9491)),
            SizedBox(height: 12),
            Text(
              'No reports yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF101617),
              ),
            ),
            SizedBox(height: 6),
            Text(
              'Any issues or feedback you submit will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF6A7774)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.report, required this.onTap});

  final IssueReport report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFFEAEFED)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                report.reference,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0E5A47),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                report.categoryLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                report.shortDescription,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF3A4644)),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    report.statusLabel,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0E5A47),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    formatIssueDate(report.createdAt),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF8A9491)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
