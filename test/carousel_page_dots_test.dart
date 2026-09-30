import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/widgets/carousel_page_dots.dart';

void main() {
  test('dot window stays at three once there are more pages', () {
    expect(carouselDotWindow(1, 0), (count: 1, active: 0));
    expect(carouselDotWindow(2, 1), (count: 2, active: 1));
    expect(carouselDotWindow(6, 0), (count: 3, active: 0));
    expect(carouselDotWindow(6, 3), (count: 3, active: 1));
    expect(carouselDotWindow(6, 5), (count: 3, active: 2));
  });

  test('one screen of items has no extra pages', () {
    final page = carouselPageFromScroll(
      offset: 0,
      maxScroll: 0,
      viewport: 360,
    );
    expect(page.count, 1);
  });

  test('scroll position maps onto later pages', () {
    final start = carouselPageFromScroll(
      offset: 0,
      maxScroll: 400,
      viewport: 200,
    );
    final end = carouselPageFromScroll(
      offset: 400,
      maxScroll: 400,
      viewport: 200,
    );
    expect(start, (active: 0, count: 3));
    expect(end.active, 2);
    expect(end.count, 3);
  });
}
