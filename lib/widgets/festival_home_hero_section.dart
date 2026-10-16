import 'package:flutter/material.dart';

import '../models/festival_banner_content.dart';
import 'festival_announcement_banner.dart';

/// Full-width festive background from the top, with foreground [child] on top.
class FestivalHomeHeroSection extends StatelessWidget {
  const FestivalHomeHeroSection({
    super.key,
    required this.content,
    required this.child,
    this.topInset = 0,
  });

  final FestivalBannerContent content;
  final Widget child;
  final double topInset;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Positioned.fill(
          child: FestivalBannerArtwork(content: content),
        ),
        if (content.hasDisplayText)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.18),
                    Colors.black.withValues(alpha: 0.08),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        Padding(
          padding: EdgeInsets.only(top: topInset),
          child: child,
        ),
      ],
    );
  }
}

/// Admin-managed title block on the hero (hidden when empty).
class FestivalHeroHeadline extends StatelessWidget {
  const FestivalHeroHeadline({super.key, required this.content});

  final FestivalBannerContent content;

  @override
  Widget build(BuildContext context) {
    if (!content.hasDisplayText) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
      child: FestivalBannerTextOverlay(content: content),
    );
  }
}
