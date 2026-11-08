import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/services/storefront_host.dart';

void main() {
  test('reads kitchen slug from subdomain host', () {
    final slug = StorefrontHost.kitchenSlugFromUri(
      Uri.parse('https://puran.societyeats.com/menu'),
    );
    expect(slug, 'puran');
  });

  test('reads kitchen slug from /kitchen path', () {
    final slug = StorefrontHost.kitchenSlugFromUri(
      Uri.parse('https://www.societyeats.com/kitchen/puran'),
    );
    expect(slug, 'puran');
  });

  test('ignores www host', () {
    final slug = StorefrontHost.kitchenSlugFromUri(
      Uri.parse('https://www.societyeats.com/'),
    );
    expect(slug, isNull);
  });

  test('apex suffix maps kitchen subdomain', () {
    final slug = StorefrontHost.kitchenSlugFromUri(
      Uri.parse('https://puran.societyeats.com/'),
    );
    expect(slug, 'puran');
  });
}
