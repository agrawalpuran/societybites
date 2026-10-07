import 'package:flutter/material.dart';

import 'content_skeleton.dart';

/// Admin first-load state: progress, message, and list-style skeletons (not a blank panel).
class AdminLoadingPanel extends StatelessWidget {
  const AdminLoadingPanel({
    super.key,
    required this.message,
    this.showSkeleton = true,
  });

  final String message;
  final bool showSkeleton;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Color(0xFF0E5A47),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  message,
                  key: const Key('admin-loading-message'),
                  style: const TextStyle(
                    color: Color(0xFF6A7774),
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          if (showSkeleton) ...[
            const SizedBox(height: 24),
            const AdminListSkeleton(),
          ],
        ],
      ),
    );
  }
}

class AdminListSkeleton extends StatelessWidget {
  const AdminListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return const Column(
      key: Key('admin-list-skeletons'),
      children: [
        _AdminRowSkeleton(),
        SizedBox(height: 10),
        _AdminRowSkeleton(),
        SizedBox(height: 10),
        _AdminRowSkeleton(),
        SizedBox(height: 10),
        _AdminRowSkeleton(),
      ],
    );
  }
}

class _AdminRowSkeleton extends StatelessWidget {
  const _AdminRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return const SkeletonCard(
      child: Row(
        children: [
          SkeletonBlock(width: 44, height: 44, radius: 12),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonBlock(width: 180, height: 16, radius: 8),
                SizedBox(height: 8),
                SkeletonBlock(height: 12),
                SizedBox(height: 6),
                SkeletonBlock(width: 120, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
