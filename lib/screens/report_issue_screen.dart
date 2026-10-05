import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/issue_report.dart';
import '../services/api_service.dart';
import '../web/web_page_frame.dart';
import 'issue_detail_screen.dart';
import 'my_reports_screen.dart';

class ReportIssueScreen extends StatefulWidget {
  const ReportIssueScreen({
    super.key,
    this.orderId,
    this.orderLabel,
    this.listingId,
    this.listingLabel,
    this.sellerId,
    this.loadReports,
  });

  final String? orderId;
  final String? orderLabel;
  final String? listingId;
  final String? listingLabel;
  final String? sellerId;
  final Future<List<IssueReport>> Function()? loadReports;

  @override
  State<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends State<ReportIssueScreen> {
  final _description = TextEditingController();
  String? _category;
  String? _error;
  bool _submitting = false;
  IssueReport? _submitted;
  List<IssueReport> _reports = const [];
  bool _loadingReports = true;
  String? _reportsError;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _loadReports() async {
    try {
      final reports = widget.loadReports != null
          ? await widget.loadReports!()
          : await ApiService.getMyIssues();
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _reportsError = null;
        _loadingReports = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _reportsError = ApiService.userFacingError(error);
        _loadingReports = false;
      });
    }
  }

  String? get _platform {
    if (kIsWeb) return 'WEB';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'ANDROID';
      case TargetPlatform.iOS:
        return 'IOS';
      default:
        return null;
    }
  }

  Future<void> _submit() async {
    final description = _description.text.trim();
    if (_category == null) {
      setState(() => _error = 'Choose a category');
      return;
    }
    if (description.isEmpty) {
      setState(() => _error = 'Tell us what happened');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final issue = await ApiService.createIssue(
        category: _category!,
        description: description,
        orderId: widget.orderId,
        listingId: widget.listingId,
        sellerId: widget.sellerId,
        platform: _platform,
      );
      if (!mounted) return;
      _description.clear();
      setState(() {
        _submitted = issue;
        _category = null;
        _reports = [issue, ..._reports.where((row) => row.id != issue.id)];
        _reportsError = null;
        _loadingReports = false;
      });
      _loadReports();
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = ApiService.userFacingError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return panelOnWeb(
      context,
      Scaffold(
        backgroundColor: const Color(0xFFF8FAF9),
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          foregroundColor: const Color(0xFF101617),
          title: const Text(
            'Report an Issue',
            style: TextStyle(
              color: Color(0xFF101617),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: _form(),
      ),
    );
  }

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
        if (_submitted != null) ...[
          const Icon(Icons.check_circle_rounded, color: Color(0xFF0E5A47), size: 36),
          const SizedBox(height: 8),
          const Text(
            'Issue submitted successfully',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Reference: ${_submitted!.reference}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0E5A47),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your issue has been submitted. It is listed below.',
            style: TextStyle(color: Color(0xFF6A7774)),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ),
          const SizedBox(height: 8),
        ],
        const Text(
          'How can we help?',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: Color(0xFF101617),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Pick a topic, then tell us what happened.',
          style: TextStyle(color: Color(0xFF6A7774)),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in IssueReport.categories.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: _category == entry.key,
                selectedColor: const Color(0xFFDCEFE8),
                labelStyle: TextStyle(
                  color: _category == entry.key
                      ? const Color(0xFF0E5A47)
                      : const Color(0xFF3A4644),
                  fontWeight: FontWeight.w600,
                ),
                onSelected: (_) => setState(() {
                  _category = entry.key;
                  _error = null;
                }),
              ),
          ],
        ),
        if (_category != null) ...[
          const SizedBox(height: 22),
          Text(
            IssueReport.categories[_category]!,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xFF0E5A47),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _description,
            minLines: 5,
            maxLines: 8,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              hintText: 'Tell us what happened...',
              filled: true,
              fillColor: Colors.white,
              counterText: '',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFEAEFED)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: Color(0xFFEAEFED)),
              ),
            ),
          ),
          if (widget.orderId != null) ...[
            const SizedBox(height: 8),
            _contextLine('Order', widget.orderLabel ?? widget.orderId!),
          ],
          if (widget.listingId != null) ...[
            const SizedBox(height: 8),
            _contextLine('Listing', widget.listingLabel ?? widget.listingId!),
          ],
        ],
        if (_error != null) ...[
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Color(0xFFD94F4F))),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0E5A47),
            minimumSize: const Size.fromHeight(48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(_submitting ? 'Submitting...' : 'Submit Report'),
        ),
        const SizedBox(height: 28),
        const Text(
          'Your reports',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        const Text(
          'Status and replies for issues you submit show up here.',
          style: TextStyle(color: Color(0xFF6A7774)),
        ),
        const SizedBox(height: 12),
        ..._reportSection(),
      ],
    );
  }

  List<Widget> _reportSection() {
    if (_loadingReports) {
      return const [
        Text(
          'Loading your reports…',
          style: TextStyle(color: Color(0xFF8A9491), fontWeight: FontWeight.w600),
        ),
      ];
    }
    if (_reportsError != null) {
      return [
        Text(_reportsError!, style: const TextStyle(color: Color(0xFFD94F4F))),
        TextButton(onPressed: _loadReports, child: const Text('Try again')),
      ];
    }
    if (_reports.isEmpty) {
      return const [
        Text(
          'No reports yet',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        SizedBox(height: 4),
        Text(
          'Any issues or feedback you submit will appear here.',
          style: TextStyle(color: Color(0xFF6A7774)),
        ),
      ];
    }
    return [
      for (final report in _reports)
        IssueReportCard(
          report: report,
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => IssueDetailScreen(issueId: report.id),
              ),
            );
            if (mounted) _loadReports();
          },
        ),
    ];
  }

  Widget _contextLine(String label, String value) {
    return Text(
      '$label: $value',
      style: const TextStyle(color: Color(0xFF3A4644), fontWeight: FontWeight.w600),
    );
  }

}
