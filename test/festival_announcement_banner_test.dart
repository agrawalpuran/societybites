import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/preview/festival_banner_preview.dart';
import 'package:societybites/models/festival_banner_content.dart';
import 'package:societybites/widgets/festival_announcement_banner.dart';
import 'package:societybites/widgets/festival_home_hero_section.dart';

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

  testWidgets('hero title is centred', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: FestivalHeroHeadline(
            content: FestivalBannerContent(title: 'Happy Diwali'),
          ),
        ),
      ),
    );
    final title = tester.widget<Text>(find.text('Happy Diwali'));
    expect(title.textAlign, TextAlign.center);
  });

  testWidgets('hero art height stays the same with or without a notch', (
    tester,
  ) async {
    const content = FestivalBannerContent(title: 'Happy Diwali');
    const width = 390.0;

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(width, 844)),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: FestivalHomeHeroSection(
                content: content,
                topInset: 0,
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
    final webHeight = tester.getSize(find.byKey(const Key('festival-hero-overlay'))).height;
    expect(find.byKey(const Key('festival-hero-artwork')), findsOneWidget);

    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(size: Size(width, 844)),
        child: MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: FestivalHomeHeroSection(
                content: content,
                topInset: 59,
                child: SizedBox.expand(),
              ),
            ),
          ),
        ),
      ),
    );
    final phoneArtHeight =
        tester.getSize(find.byKey(const Key('festival-hero-overlay'))).height;
    expect(find.byKey(const Key('festival-hero-artwork')), findsOneWidget);
    expect(phoneArtHeight, closeTo(webHeight, 0.5));
    expect(webHeight, closeTo(width / kFestivalHeroAspectRatio, 0.5));
  });
}
