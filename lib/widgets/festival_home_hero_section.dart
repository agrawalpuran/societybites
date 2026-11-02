import 'package:flutter/material.dart';

import '../models/festival_banner_content.dart';
import 'festival_announcement_banner.dart';

/// Width / height of the hero below the status bar. Same crop on web and iPhone.
const double kFestivalHeroAspectRatio = 1.95;

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
    final inset = topInset > 0 ? topInset : 0.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final overlayHeight = width / kFestivalHeroAspectRatio;
        return SizedBox(
          height: inset + overlayHeight,
          width: width,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: FestivalBannerArtwork(
                  key: const Key('festival-hero-artwork'),
                  content: content,
                  alignment: Alignment.topCenter,
                ),
              ),
              if (content.hasDisplayText)
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x2E000000),
                          Color(0x14000000),
                          Color(0x00000000),
                        ],
                      ),
                    ),
                  ),
                ),
              Positioned(
                key: const Key('festival-hero-overlay'),
                top: inset,
                left: 0,
                right: 0,
                height: overlayHeight,
                child: child,
              ),
            ],
          ),
        );
      },
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
      child: FestivalBannerTextOverlay(
        content: content,
        align: TextAlign.center,
      ),
    );
  }
}
