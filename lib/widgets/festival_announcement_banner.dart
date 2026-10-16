import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/festival_banner_content.dart';
import '../preview/festival_banner_preview.dart';

/// Full-width festive banner matching SocietyEats home margins (20px).
class FestivalAnnouncementBanner extends StatelessWidget {
  const FestivalAnnouncementBanner({
    super.key,
    required this.content,
  });

  final FestivalBannerContent content;

  static const _radius = 16.0;
  static const _horizontalMargin = 20.0;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        _horizontalMargin,
        12,
        _horizontalMargin,
        4,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_radius),
        child: AspectRatio(
          aspectRatio: 2.75,
          child: Stack(
            fit: StackFit.expand,
            children: [
              FestivalBannerArtwork(content: content),
              if (content.hasDisplayText)
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withValues(alpha: 0.55),
                        Colors.black.withValues(alpha: 0.12),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              if (content.hasDisplayText)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: FestivalBannerTextOverlay(content: content),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Title + subtitle overlay (admin-managed).
class FestivalBannerTextOverlay extends StatelessWidget {
  const FestivalBannerTextOverlay({super.key, required this.content});

  final FestivalBannerContent content;

  @override
  Widget build(BuildContext context) {
    if (!content.hasDisplayText) return const SizedBox.shrink();

    final title = content.title?.trim() ?? '';
    final subtitle = content.subtitle?.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (title.isNotEmpty)
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              height: 1.15,
              shadows: [
                Shadow(color: Colors.black38, blurRadius: 6),
              ],
            ),
          ),
        if (subtitle.isNotEmpty) ...[
          if (title.isNotEmpty) const SizedBox(height: 6),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.95),
              fontSize: 12,
              fontWeight: FontWeight.w600,
              height: 1.25,
              shadows: const [
                Shadow(color: Colors.black38, blurRadius: 4),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Shared artwork for card banner and home hero backdrop.
class FestivalBannerArtwork extends StatelessWidget {
  const FestivalBannerArtwork({super.key, required this.content});

  final FestivalBannerContent content;

  @override
  Widget build(BuildContext context) {
    final url = content.imageUrl?.trim();
    if (url != null && url.isNotEmpty) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const FestivalBannerPlaceholderArtwork(),
      );
    }
    final path = content.imageAssetPath?.trim();
    if (path != null && path.isNotEmpty) {
      return _FestivalBannerAssetImage(path: path);
    }
    return const FestivalBannerPlaceholderArtwork();
  }
}

/// Tries PNG then JPG for the bundled preview filename.
class _FestivalBannerAssetImage extends StatelessWidget {
  const _FestivalBannerAssetImage({
    required this.path,
    this.tryIndex = 0,
  });

  final String path;
  final int tryIndex;

  List<String> get _candidates {
    if (path == FestivalBannerContent.previewAssetPath ||
        path == FestivalBannerContent.previewAssetPathJpg) {
      return FestivalBannerContent.previewAssetPaths;
    }
    return [path];
  }

  @override
  Widget build(BuildContext context) {
    final candidates = _candidates;
    if (tryIndex >= candidates.length) {
      return const FestivalBannerPlaceholderArtwork();
    }
    final asset = candidates[tryIndex];
    return Image.asset(
      asset,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) => _FestivalBannerAssetImage(
        path: path,
        tryIndex: tryIndex + 1,
      ),
    );
  }
}

/// Neutral slot until admin provides an image (no festival copy in the app).
class FestivalBannerPlaceholderArtwork extends StatelessWidget {
  const FestivalBannerPlaceholderArtwork({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFFE8EEE9),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxHeight < 88;
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.image_outlined,
                  size: compact ? 28 : 40,
                  color: const Color(0xFF8A9491).withValues(alpha: 0.9),
                ),
                if (kDebugMode && !compact) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Banner image',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF8A9491),
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Renders nothing for inactive / loading / error — home feed stays intact.
Widget? buildFestivalBannerIfActive({
  required FestivalBannerPreviewState state,
  FestivalBannerContent? content,
}) {
  final bannerContent =
      content ?? FestivalBannerPreview.instance.content;
  switch (state) {
    case FestivalBannerPreviewState.active:
      return FestivalAnnouncementBanner(content: bannerContent);
    case FestivalBannerPreviewState.hidden:
    case FestivalBannerPreviewState.loading:
    case FestivalBannerPreviewState.error:
      return null;
  }
}
