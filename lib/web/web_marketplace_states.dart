import 'package:flutter/material.dart';

import '../widgets/app_header.dart';
import 'web_breakpoints.dart';

class WebStartupFrame extends StatelessWidget {
  const WebStartupFrame({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: webPageBackground,
      body: Column(
        children: [
          _StartupBar(),
          Expanded(
            child: SingleChildScrollView(child: WebMarketplaceSkeleton()),
          ),
        ],
      ),
    );
  }
}

class _StartupBar extends StatelessWidget {
  const _StartupBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 64,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: webLine)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      alignment: Alignment.centerLeft,
      child: const Text(
        kAppDisplayName,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 20,
          color: webGreenDark,
        ),
      ),
    );
  }
}

class WebMarketplaceSkeleton extends StatefulWidget {
  const WebMarketplaceSkeleton({super.key, this.isSlow = false, this.onRetry});

  final bool isSlow;
  final VoidCallback? onRetry;

  @override
  State<WebMarketplaceSkeleton> createState() => _WebMarketplaceSkeletonState();
}

class _WebMarketplaceSkeletonState extends State<WebMarketplaceSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1).animate(_pulse),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final columns = webFoodColumnCount(width);
          final pad = webPagePadding(width);
          return Padding(
            padding: EdgeInsets.fromLTRB(pad, 22, pad, 40),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: webFrameMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _Block(height: 220, radius: 22),
                    const SizedBox(height: 28),
                    const _Block(width: 180, height: 14),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 96,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: 6,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (_, _) => const _Block(
                          width: 150,
                          height: 96,
                          radius: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const _Block(width: 260, height: 18),
                    const SizedBox(height: 14),
                    _Grid(columns: columns, count: columns * 2),
                    if (widget.isSlow) ...[
                      const SizedBox(height: 18),
                      TextButton.icon(
                        onPressed: widget.onRetry,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Retry'),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class WebMarketplaceError extends StatelessWidget {
  const WebMarketplaceError({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: webLine),
      ),
      child: Column(
        children: [
          const Icon(Icons.wifi_off_rounded, color: webGreen, size: 28),
          const SizedBox(height: 12),
          const Text(
            "We couldn't load the marketplace",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: webInk,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 14,
              height: 1.4,
              color: webMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            style: FilledButton.styleFrom(
              backgroundColor: webGreen,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.columns, required this.count});

  final int columns;
  final int count;

  @override
  Widget build(BuildContext context) {
    final rows = (count / columns).ceil();
    return Column(
      children: [
        for (var row = 0; row < rows; row++) ...[
          Row(
            children: [
              for (var col = 0; col < columns; col++) ...[
                if (col > 0) const SizedBox(width: 16),
                const Expanded(child: _Block(height: 230, radius: 16)),
              ],
            ],
          ),
          if (row != rows - 1) const SizedBox(height: 16),
        ],
      ],
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({this.width, required this.height, this.radius = 10});

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: const Color(0xFFE4EBE6),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
