import 'package:flutter/material.dart';

import 'preorder_widgets.dart';

const loadSlowThreshold = Duration(seconds: 8);

class SkeletonBlock extends StatelessWidget {
  const SkeletonBlock({
    super.key,
    this.width,
    this.height = 14,
    this.radius = 6,
  });

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFEAEFED),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: preorderBorder),
      ),
      child: child,
    );
  }
}

class HomeFeedSkeleton extends StatelessWidget {
  const HomeFeedSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        key: Key('home-feed-skeletons'),
        children: [
          _HomeListingSkeleton(),
          SizedBox(height: 12),
          _HomeListingSkeleton(),
          SizedBox(height: 12),
          _HomeListingSkeleton(),
        ],
      ),
    );
  }
}

class _HomeListingSkeleton extends StatelessWidget {
  const _HomeListingSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonCard(
      child: Row(
        children: [
          SkeletonBlock(width: 72, height: 72, radius: 14),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBlock(width: 160, height: 16, radius: 8),
                SizedBox(height: 8),
                SkeletonBlock(height: 12),
                SizedBox(height: 8),
                SkeletonBlock(width: 88, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class KitchenOrdersSkeleton extends StatelessWidget {
  const KitchenOrdersSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Column(
        key: Key('kitchen-orders-skeletons'),
        children: [
          _OrderSkeletonCard(),
          SizedBox(height: 12),
          _OrderSkeletonCard(),
          SizedBox(height: 12),
          _OrderSkeletonCard(),
        ],
      ),
    );
  }
}

class KitchenPreOrdersSkeleton extends StatelessWidget {
  const KitchenPreOrdersSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      key: Key('kitchen-preorder-skeletons'),
      children: [
        _OrderSkeletonCard(),
        SizedBox(height: 12),
        _OrderSkeletonCard(),
      ],
    );
  }
}

class KitchenDashboardSkeleton extends StatelessWidget {
  const KitchenDashboardSkeleton({super.key, this.padded = true});

  final bool padded;

  @override
  Widget build(BuildContext context) {
    final body = const Column(
      key: Key('kitchen-dashboard-skeletons'),
      children: [
        SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBlock(width: 120, height: 14),
              SizedBox(height: 12),
              SkeletonBlock(width: 80, height: 28, radius: 8),
            ],
          ),
        ),
        SizedBox(height: 12),
        SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBlock(width: 160, height: 16, radius: 8),
              SizedBox(height: 14),
              SkeletonBlock(height: 12),
              SizedBox(height: 8),
              SkeletonBlock(width: 200, height: 12),
              SizedBox(height: 8),
              SkeletonBlock(width: 140, height: 12),
            ],
          ),
        ),
        SizedBox(height: 12),
        SkeletonCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBlock(width: 100, height: 16, radius: 8),
              SizedBox(height: 14),
              SkeletonBlock(height: 72, radius: 12),
            ],
          ),
        ),
      ],
    );
    if (!padded) return body;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: body,
    );
  }
}

class PreOrderDetailSkeleton extends StatelessWidget {
  const PreOrderDetailSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        key: Key('preorder-detail-skeletons'),
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBlock(height: 180, radius: 20),
          SizedBox(height: 18),
          SkeletonBlock(width: 220, height: 22, radius: 8),
          SizedBox(height: 14),
          SkeletonCard(
            child: Column(
              children: [
                SkeletonBlock(height: 14),
                SizedBox(height: 10),
                SkeletonBlock(width: 160, height: 14),
              ],
            ),
          ),
          SizedBox(height: 12),
          SkeletonCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBlock(width: 140, height: 16, radius: 8),
                SizedBox(height: 10),
                SkeletonBlock(height: 14),
                SizedBox(height: 8),
                SkeletonBlock(width: 96, height: 14),
              ],
            ),
          ),
          SizedBox(height: 12),
          SkeletonBlock(height: 48, radius: 15),
        ],
      ),
    );
  }
}

class _OrderSkeletonCard extends StatelessWidget {
  const _OrderSkeletonCard();

  @override
  Widget build(BuildContext context) {
    return const SkeletonCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SkeletonBlock(width: 180, height: 16, radius: 8),
          SizedBox(height: 10),
          SkeletonBlock(height: 12),
          SizedBox(height: 8),
          SkeletonBlock(width: 120, height: 12),
        ],
      ),
    );
  }
}

class InlineLoadStatus extends StatelessWidget {
  const InlineLoadStatus.slow({super.key, required this.onRetry, this.id = 'load'})
    : failed = false,
      detail = null;

  const InlineLoadStatus.failed({
    super.key,
    required this.onRetry,
    this.detail,
    this.id = 'load',
  }) : failed = true;

  final VoidCallback onRetry;
  final bool failed;
  final String? detail;
  final String id;

  @override
  Widget build(BuildContext context) {
    final title = failed
        ? "We couldn't load this right now."
        : 'Taking longer than expected.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        key: Key(failed ? '$id-failed-status' : '$id-slow-status'),
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: preorderBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                color: preorderText,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (failed) ...[
              const SizedBox(height: 4),
              const Text(
                'Please check your connection and try again.',
                style: TextStyle(
                  color: preorderMuted,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (detail != null && detail!.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  detail!,
                  style: const TextStyle(
                    color: Color(0xFFD94F4F),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
            const SizedBox(height: 12),
            OutlinedButton(
              key: Key(failed ? '$id-try-again' : '$id-refresh'),
              onPressed: onRetry,
              style: OutlinedButton.styleFrom(
                foregroundColor: preorderGreen,
                side: const BorderSide(color: Color(0xFFD4E8DF)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(failed ? 'Try again' : 'Refresh'),
            ),
          ],
        ),
      ),
    );
  }
}
