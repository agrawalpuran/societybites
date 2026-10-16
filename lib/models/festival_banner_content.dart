/// Admin / API payload for a home festival or announcement banner.
class FestivalBannerContent {
  const FestivalBannerContent({
    this.title,
    this.subtitle,
    this.imageAssetPath,
    this.imageUrl,
  });

  final String? title;
  final String? subtitle;
  final String? imageAssetPath;
  final String? imageUrl;

  /// Default local preview file (admin toggle). PNG or JPG both work.
  static const previewAssetPath =
      'assets/images/preview/festival_banner_preview.png';

  static const previewAssetPathJpg =
      'assets/images/preview/festival_banner_preview.jpg';

  static const previewAssetPaths = [
    previewAssetPath,
    previewAssetPathJpg,
  ];

  bool get hasDisplayText {
    final t = title?.trim() ?? '';
    final s = subtitle?.trim() ?? '';
    return t.isNotEmpty || s.isNotEmpty;
  }

  bool get hasImage =>
      (imageUrl?.trim().isNotEmpty ?? false) ||
      (imageAssetPath?.trim().isNotEmpty ?? false);

  static const FestivalBannerContent placeholder = FestivalBannerContent();

  factory FestivalBannerContent.fromJson(Map<String, dynamic> json) {
    return FestivalBannerContent(
      title: json['title'] as String?,
      subtitle: json['subtitle'] as String?,
      imageUrl: json['imageUrl'] as String?,
      imageAssetPath: json['imageAssetPath'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        if (title != null) 'title': title,
        if (subtitle != null) 'subtitle': subtitle,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (imageAssetPath != null) 'imageAssetPath': imageAssetPath,
      };
}
