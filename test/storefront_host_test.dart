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

  test('normalizeKitchenSlug rejects seller user ids', () {
    expect(
      StorefrontHost.normalizeKitchenSlug(
        '1a33632e-7d58-4691-99a1-7b2f22a6cc75',
      ),
      isNull,
    );
    expect(StorefrontHost.normalizeKitchenSlug('puran'), 'puran');
  });

  test('ignores /s/:sellerId paths for kitchen slug', () {
    final slug = StorefrontHost.kitchenSlugFromUri(
      Uri.parse(
        'https://societyeats.vercel.app/s/1a33632e-7d58-4691-99a1-7b2f22a6cc75',
      ),
    );
    expect(slug, isNull);
  });

  test('does not treat societyeats.vercel.app as a kitchen subdomain', () {
    final slug = StorefrontHost.kitchenSlugFromUri(
      Uri.parse(
        'https://societyeats.vercel.app/s/1a33632e-7d58-4691-99a1-7b2f22a6cc75',
      ),
    );
    expect(slug, isNot('societyeats'));
    expect(slug, isNull);
  });
}
