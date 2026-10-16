import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/preview/festival_banner_preview.dart';
import 'package:societybites/models/festival_banner_content.dart';
import 'package:societybites/widgets/festival_announcement_banner.dart';

void main() {
  test('inactive states do not reserve banner space', () {
    expect(
      buildFestivalBannerIfActive(state: FestivalBannerPreviewState.hidden),
      isNull,
    );
    expect(
      buildFestivalBannerIfActive(state: FestivalBannerPreviewState.loading),
      isNull,
    );
    expect(
      buildFestivalBannerIfActive(state: FestivalBannerPreviewState.error),
      isNull,
    );
  });

  test('active state returns banner widget', () {
    final widget = buildFestivalBannerIfActive(
      state: FestivalBannerPreviewState.active,
      content: const FestivalBannerContent(title: 'Test'),
    );
    expect(widget, isNotNull);
    expect(widget, isA<FestivalAnnouncementBanner>());
  });
}
