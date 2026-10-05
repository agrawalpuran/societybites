import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/issue_report.dart';
import '../services/api_service.dart';
import '../web/web_page_frame.dart';
import '../widgets/photo_source_sheet.dart';
import '../widgets/screen_loading_note.dart';

class IssueDetailScreen extends StatefulWidget {
  const IssueDetailScreen({super.key, required this.issueId, this.initial});

  final String issueId;
  final IssueReport? initial;

  @override
  State<IssueDetailScreen> createState() => _IssueDetailScreenState();
}

class _IssueDetailScreenState extends State<IssueDetailScreen> {
  final _reply = TextEditingController();
  final _picker = ImagePicker();
  IssueReport? _issue;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  String? _replyError;
  List<int>? _photoBytes;
  String _photoMime = 'image/jpeg';

  @override
  void initState() {
    super.initState();
    _issue = widget.initial;
    _load();
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
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

  Future<void> _pickPhoto() async {
    final source = await showPhotoSourceSheet(context, title: 'Add a photo');
    if (source == null || !mounted) return;
    final file = await _picker.pickImage(
      source: source,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;
    setState(() {
      _photoBytes = bytes;
      _photoMime = file.mimeType ?? 'image/jpeg';
    });
  }

  Future<void> _sendReply() async {
    final text = _reply.text.trim();
    if (text.isEmpty && _photoBytes == null) {
      setState(() => _replyError = 'Write a reply or add a photo');
      return;
    }
    setState(() {
      _sending = true;
      _replyError = null;
    });
    try {
      String? imageUrl;
      if (_photoBytes != null) {
        imageUrl = await ApiService.uploadListingImage(
          bytes: _photoBytes!,
          mimeType: _photoMime,
          purpose: 'issue',
        );
      }
      final issue = await ApiService.replyToIssue(
        widget.issueId,
        body: text,
        imageUrl: imageUrl,
      );
      if (!mounted) return;
      _reply.clear();
      setState(() {
        _issue = issue;
        _photoBytes = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _replyError = ApiService.userFacingError(error));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  List<IssueMessage> _visibleThread(IssueReport issue) {
    if (issue.messages.isNotEmpty) return issue.messages;
    return [
      IssueMessage(
        id: '${issue.id}-opened',
        authorRole: 'USER',
        body: issue.description,
        createdAt: issue.createdAt,
        imageUrl: issue.imageUrl,
      ),
      if (issue.adminResponse != null)
        IssueMessage(
          id: '${issue.id}-admin',
          authorRole: 'SOCIETYEATS',
          body: issue.adminResponse!,
          createdAt: issue.createdAt,
        ),
    ];
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
                            'Submitted ${formatIssueDateTimeIst(issue.createdAt)}',
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
                          if (issue.imageUrl != null) ...[
                            const SizedBox(height: 16),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Image.network(
                                issue.imageUrl!,
                                height: 180,
                                width: double.infinity,
                                fit: BoxFit.cover,
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          const Text(
                            'Conversation',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 10),
                          for (final message in _visibleThread(issue))
                            IssueMessageTile(
                              message: message,
                              label: message.isSocietyEats ? 'SocietyEats' : 'You',
                            ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            children: [
                              ActionChip(
                                label: const Text('This is resolved'),
                                onPressed: _sending
                                    ? null
                                    : () => _reply.text = 'This is resolved',
                              ),
                              ActionChip(
                                label: const Text('Still an issue'),
                                onPressed: _sending
                                    ? null
                                    : () => _reply.text = 'This is still an issue',
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _reply,
                            minLines: 2,
                            maxLines: 5,
                            maxLength: 2000,
                            decoration: const InputDecoration(
                              hintText: 'Reply to SocietyEats...',
                              filled: true,
                              fillColor: Colors.white,
                            ),
                          ),
                          if (_photoBytes != null)
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text(
                                'Photo attached',
                                style: TextStyle(
                                  color: Color(0xFF0E5A47),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: _sending ? null : _pickPhoto,
                                icon: const Icon(Icons.photo_camera_outlined),
                                label: const Text('Photo'),
                              ),
                              const Spacer(),
                              FilledButton(
                                onPressed: _sending ? null : _sendReply,
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF0E5A47),
                                ),
                                child: Text(_sending ? 'Sending...' : 'Send'),
                              ),
                            ],
                          ),
                          if (_replyError != null)
                            Text(
                              _replyError!,
                              style: const TextStyle(color: Color(0xFFD94F4F)),
                            ),
                        ],
                      ),
      ),
    );
  }
}

class IssueMessageTile extends StatelessWidget {
  const IssueMessageTile({
    super.key,
    required this.message,
    required this.label,
  });

  final IssueMessage message;
  final String label;

  @override
  Widget build(BuildContext context) {
    final fromSociety = message.isSocietyEats;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fromSociety ? const Color(0xFFE7F3EE) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(
            formatIssueDateTimeIst(message.createdAt),
            style: const TextStyle(fontSize: 12, color: Color(0xFF6A7774)),
          ),
          if (message.body.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(message.body, style: const TextStyle(height: 1.4)),
          ],
          if (message.imageUrl != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                message.imageUrl!,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
