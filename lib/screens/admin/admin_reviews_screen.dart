import 'package:flutter/material.dart';

import '../../services/api_service.dart';

class AdminReviewsScreen extends StatefulWidget {
  const AdminReviewsScreen({super.key});

  @override
  State<AdminReviewsScreen> createState() => _AdminReviewsScreenState();
}

class _AdminReviewsScreenState extends State<AdminReviewsScreen> {
  List<Map<String, dynamic>> _reviews = [];
  bool _isLoading = true;
  String? _error;
  int _page = 1;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews({bool reset = true}) async {
    if (reset) {
      setState(() {
        _page = 1;
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final data = await ApiService.getAdminReviews(page: _page);
      if (!mounted) return;
      setState(() {
        if (reset) {
          _reviews = data;
        } else {
          _reviews.addAll(data);
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
    _loadReviews(reset: false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading && _reviews.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
      );
    }
    if (_error != null && _reviews.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Color(0xFF6A7774))),
            const SizedBox(height: 12),
            ElevatedButton(onPressed: _loadReviews, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_reviews.isEmpty) {
      return const Center(
        child:
            Text('No reviews yet', style: TextStyle(color: Color(0xFF6A7774))),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF0E5A47),
      onRefresh: _loadReviews,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _reviews.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == _reviews.length) {
            _loadMore();
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
              ),
            );
          }

          final review = _reviews[index];
          final reviewer =
              (review['user'] as Map<String, dynamic>?)?['name']?.toString() ??
                  'Anonymous';
          final listing = (review['listing'] as Map<String, dynamic>?)
                  ?['name']
                  ?.toString() ??
              '—';
          final rating = review['rating'] ?? 0;
          final comment = review['comment']?.toString() ?? '';
          final createdAt = review['createdAt']?.toString() ?? '';

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
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
                      ...List.generate(5, (i) {
                        return Icon(
                          i < (rating as int) ? Icons.star : Icons.star_border,
                          size: 16,
                          color: const Color(0xFFF9A825),
                        );
                      }),
                      const Spacer(),
                      Text(
                        _formatDate(createdAt),
                        style: const TextStyle(
                            fontSize: 11, color: Color(0xFF8A9491)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (comment.isNotEmpty)
                    Text(
                      comment,
                      style: const TextStyle(
                          fontSize: 13, color: Color(0xFF101617)),
                    ),
                  if (comment.isNotEmpty) const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 13, color: Color(0xFF8A9491)),
                      const SizedBox(width: 4),
                      Text(
                        reviewer,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF6A7774)),
                      ),
                      const SizedBox(width: 16),
                      const Icon(Icons.fastfood_rounded,
                          size: 13, color: Color(0xFF8A9491)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          listing,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF6A7774)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDate(String iso) {
    if (iso.isEmpty) return '—';
    try {
      final d = DateTime.parse(iso);
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return iso;
    }
  }
}
