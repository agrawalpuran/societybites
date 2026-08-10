import 'package:flutter/material.dart';

import '../models/data.dart';
import '../services/api_service.dart';
import '../widgets/app_header.dart';

class SellerFeedbackScreen extends StatefulWidget {
  const SellerFeedbackScreen({super.key});

  @override
  State<SellerFeedbackScreen> createState() => _SellerFeedbackScreenState();
}

class _SellerFeedbackScreenState extends State<SellerFeedbackScreen> {
  List<Review> _reviews = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _cleanError(Object e) {
    var message = e.toString();
    if (message.startsWith('Exception: ')) {
      message = message.substring('Exception: '.length);
    }
    return message;
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final raw = await ApiService.getSellerReviews();
      final reviews = raw.map(Review.fromJson).toList();
      if (!mounted) return;
      setState(() {
        _reviews = reviews;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _cleanError(e);
        _isLoading = false;
      });
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '';
    final local = dt.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/'
        '${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppHeader(
              padding: const EdgeInsets.fromLTRB(4, 10, 20, 0),
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                color: const Color(0xFF3A4644),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 12, 20, 8),
              child: Text(
                'Feedback',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101617),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                _isLoading
                    ? 'Loading reviews…'
                    : _reviews.isEmpty
                        ? 'Reviews from neighbors appear here.'
                        : '${_reviews.length} review${_reviews.length == 1 ? '' : 's'} received',
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF6A7774),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF0E5A47),
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _error!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: Color(0xFFD94F4F),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                TextButton(
                                  onPressed: _load,
                                  child: const Text('Retry'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : _reviews.isEmpty
                          ? const Center(
                              child: Text(
                                'No feedback yet',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                  color: Color(0xFF3A4644),
                                ),
                              ),
                            )
                          : RefreshIndicator(
                              color: const Color(0xFF0E5A47),
                              onRefresh: _load,
                              child: ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(
                                  parent: BouncingScrollPhysics(),
                                ),
                                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                                itemCount: _reviews.length,
                                itemBuilder: (_, index) {
                                  final review = _reviews[index];
                                  return _FeedbackCard(
                                    review: review,
                                    dateLabel: _formatDate(review.createdAt),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({
    required this.review,
    required this.dateLabel,
  });

  final Review review;
  final String dateLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  review.listingName?.isNotEmpty == true
                      ? review.listingName!
                      : 'Listing',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    color: Color(0xFF101617),
                  ),
                ),
              ),
              ...List.generate(5, (i) {
                return Icon(
                  Icons.star_rounded,
                  size: 16,
                  color: i < review.rating.round()
                      ? Colors.amber
                      : const Color(0xFFE0E5E3),
                );
              }),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            [
              review.displayName,
              if (dateLabel.isNotEmpty) dateLabel,
            ].join(' · '),
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF8A9491),
              fontWeight: FontWeight.w500,
            ),
          ),
          if (review.comment.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              review.comment,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF3A4644),
                height: 1.4,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          if (review.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: review.tags
                  .map(
                    (tag) => Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF5F7F6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        tag,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6A7774),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}
