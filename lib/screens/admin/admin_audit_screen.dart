import 'package:flutter/material.dart';

import '../../services/api_service.dart';

class AdminAuditScreen extends StatefulWidget {
  const AdminAuditScreen({super.key});

  @override
  State<AdminAuditScreen> createState() => _AdminAuditScreenState();
}

class _AdminAuditScreenState extends State<AdminAuditScreen> {
  List<Map<String, dynamic>> _logs = [];
  bool _isLoading = true;
  String? _error;
  int _page = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs({bool reset = true}) async {
    if (reset) {
      setState(() {
        _page = 1;
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final data = await ApiService.getAdminAuditLog(page: _page);
      if (!mounted) return;
      setState(() {
        if (reset) {
          _logs = data;
        } else {
          _logs.addAll(data);
        }
        _hasMore = data.length >= 20;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _loadMore() {
    if (!_hasMore || _isLoading) return;
    _page++;
    _loadLogs(reset: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _logs.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
      );
    }
    if (_error != null && _logs.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Color(0xFF6A7774))),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadLogs, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_logs.isEmpty) {
      return const Center(
        child: Text('No audit logs yet',
            style: TextStyle(color: Color(0xFF6A7774))),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF0E5A47),
      onRefresh: _loadLogs,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _logs.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _logs.length) {
            _loadMore();
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
              ),
            );
          }

          final log = _logs[index];
          final adminName =
              (log['admin'] as Map<String, dynamic>?)?['name']?.toString() ??
                  log['adminName']?.toString() ??
                  '—';
          final action = log['action']?.toString() ?? '—';
          final target = log['target']?.toString() ??
              log['targetType']?.toString() ??
              '';
          final targetId = log['targetId']?.toString() ?? '';
          final timestamp = log['createdAt']?.toString() ??
              log['timestamp']?.toString() ??
              '';
          final details = log['details']?.toString() ?? '';

          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5EE),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.history_rounded,
                          size: 16,
                          color: Color(0xFF0E5A47),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              action,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: Color(0xFF101617),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'by $adminName',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6A7774),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _formatDateTime(timestamp),
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF8A9491)),
                      ),
                    ],
                  ),
                  if (target.isNotEmpty || targetId.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const SizedBox(width: 44),
                        if (target.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF0F2F1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              target,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6A7774),
                              ),
                            ),
                          ),
                        if (targetId.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Text(
                            targetId,
                            style: const TextStyle(
                                fontSize: 11, color: Color(0xFF8A9491)),
                          ),
                        ],
                      ],
                    ),
                  ],
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Padding(
                      padding: const EdgeInsets.only(left: 44),
                      child: Text(
                        details,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF6A7774)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDateTime(String iso) {
    if (iso.isEmpty) return '—';
    try {
      final d = DateTime.parse(iso);
      return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return iso;
    }
  }
}
