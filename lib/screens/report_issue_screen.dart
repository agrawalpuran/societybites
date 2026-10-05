import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/issue_report.dart';
import '../services/api_service.dart';
import '../web/web_page_frame.dart';
import 'my_reports_screen.dart';

class ReportIssueScreen extends StatefulWidget {
  const ReportIssueScreen({
    super.key,
    this.orderId,
    this.orderLabel,
    this.listingId,
    this.listingLabel,
    this.sellerId,
  });

  final String? orderId;
  final String? orderLabel;
  final String? listingId;
  final String? listingLabel;
  final String? sellerId;

  @override
  State<ReportIssueScreen> createState() => _ReportIssueScreenState();
}

class _ReportIssueScreenState extends State<ReportIssueScreen> {
  final _description = TextEditingController();
  String? _category;
  String? _error;
  bool _submitting = false;
  IssueReport? _submitted;

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
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
      setState(() => _submitted = issue);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = ApiService.userFacingError(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
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
          title: Text(
            _submitted == null ? 'How can we help?' : 'Issue submitted',
            style: const TextStyle(
              color: Color(0xFF101617),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        body: _submitted == null ? _form() : _confirmation(),
      ),
    );
  }

  Widget _form() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      children: [
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
      ],
    );
  }

  Widget _contextLine(String label, String value) {
    return Text(
      '$label: $value',
      style: const TextStyle(color: Color(0xFF3A4644), fontWeight: FontWeight.w600),
    );
  }

  Widget _confirmation() {
    final issue = _submitted!;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_rounded, color: Color(0xFF0E5A47), size: 42),
          const SizedBox(height: 12),
          const Text(
            'Issue submitted successfully',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your issue has been submitted.',
            style: TextStyle(color: Color(0xFF6A7774)),
          ),
          const SizedBox(height: 16),
          Text(
            'Reference: ${issue.reference}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0E5A47),
            ),
          ),
          const Spacer(),
          FilledButton(
            onPressed: () {
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(builder: (_) => const MyReportsScreen()),
              );
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0E5A47),
              minimumSize: const Size.fromHeight(48),
            ),
            child: const Text('View My Reports'),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }
}
