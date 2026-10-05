import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/api_service.dart';

/// Circular seller avatar. Uses one [photoUrl] everywhere; falls back to [fallback]
/// when missing or if the image fails to load.
class SellerAvatar extends StatelessWidget {
  const SellerAvatar({
    super.key,
    required this.radius,
    required this.backgroundColor,
    required this.fallback,
    this.photoUrl,
    this.ringColor,
    this.ringWidth = 0,
    this.muted = false,
  });

  final double radius;
  final Color backgroundColor;
  final Widget fallback;
  final String? photoUrl;
  final Color? ringColor;
  final double ringWidth;

  /// Greyscale and soft blur for a profile photo. The fallback icon stays sharp.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final hasRing = ringColor != null && ringWidth > 0;
    final innerSize = hasRing ? (size - ringWidth * 2).clamp(0.0, size) : size;
    final url = photoUrl?.trim();
    final hasUrl = url != null && url.isNotEmpty && url != 'null';
    final avatar = ClipOval(
      child: Container(
        width: innerSize,
        height: innerSize,
        color: backgroundColor,
        alignment: Alignment.center,
        child: hasUrl
            ? _photo(ApiService.imageUrl(url!), innerSize, context)
            : fallback,
      ),
    );

    if (!hasRing) return avatar;

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor!, width: ringWidth),
      ),
      child: avatar,
    );
  }

  Widget _photo(String url, double size, BuildContext context) {
    final image = Image.network(
      url,
      webHtmlElementStrategy: WebHtmlElementStrategy.never,
      width: size,
      height: size,
      fit: BoxFit.cover,
      cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(
        48,
        512,
      ),
      errorBuilder: (_, _, _) => fallback,
    );
    if (!muted) return image;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0.2126,
        0.7152,
        0.0722,
        0,
        0,
        0,
        0,
        0,
        1,
        0,
      ]),
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 2.2, sigmaY: 2.2),
        child: image,
      ),
    );
  }
}
