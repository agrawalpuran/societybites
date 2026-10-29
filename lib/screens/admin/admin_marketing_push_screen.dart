import 'package:flutter/material.dart';

import '../../services/api_service.dart';

/// Super-admin screen to send at most one marketing FCM broadcast per week.
class AdminMarketingPushScreen extends StatefulWidget {
  const AdminMarketingPushScreen({super.key});

  @override
  State<AdminMarketingPushScreen> createState() =>
      _AdminMarketingPushScreenState();
}

class _AdminMarketingPushScreenState extends State<AdminMarketingPushScreen> {
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  bool _loading = true;
  bool _sending = false;
  String? _error;
  Map<String, dynamic>? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await ApiService.getAdminMarketingPushStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = ApiService.userFacingError(e);
      });
    }
  }

  bool get _canSend => _status?['canSend'] == true && !_sending;

  String _statusSummary() {
    final tokens = _status?['activeTokenCount'] ?? 0;
    if (_status?['canSend'] == true) {
      return 'Ready to send. $tokens active device(s). Limit: 1 per week.';
    }
    final next = _status?['nextAllowedAt']?.toString();
    final when = next == null || next.isEmpty
        ? 'later'
        : DateTime.tryParse(next)?.toLocal().toString().split('.').first ?? next;
    return 'Already sent this week. Next allowed after $when. ($tokens devices)';
  }

  Future<void> _confirmAndSend() async {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty || body.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Title and body are required')),
      );
      return;
    }

    final tokens = _status?['activeTokenCount'] ?? 0;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Send marketing push?'),
        content: Text(
          'This notifies about $tokens devices and locks further marketing '
          'pushes for 7 days.\n\n"$title"\n$body',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _sending = true);
    try {
      final result = await ApiService.sendAdminMarketingPush(
        title: title,
        body: body,
      );
      if (!mounted) return;
      setState(() {
        _status = {
          ...?_status,
          'canSend': false,
          'lastSentAt': result['lastSentAt'],
          'nextAllowedAt': result['nextAllowedAt'],
        };
        _sending = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Sent to ${result['sent'] ?? 0} of ${result['tokenCount'] ?? 0} devices',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.userFacingError(e))),
      );
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F8F7),
      appBar: AppBar(
        title: const Text('Marketing push'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF101617),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_error != null) ...[
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 12),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                  const SizedBox(height: 16),
                ],
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFEAEFED)),
                  ),
                  child: Text(
                    _statusSummary(),
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF3A4744),
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _titleController,
                  enabled: _canSend,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    hintText: 'e.g. Fresh kitchens near you',
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _bodyController,
                  enabled: _canSend,
                  maxLength: 160,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Body',
                    hintText: 'Short nudge — keep it useful, not spammy',
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: _canSend ? _confirmAndSend : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0E5A47),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  child: _sending
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Send this week\'s push'),
                ),
              ],
            ),
    );
  }
}
