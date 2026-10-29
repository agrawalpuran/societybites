import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/services/deep_link_service.dart';

void main() {
  setUp(DeepLinkService.resetForTest);

  test('parses /s/:sellerId paths', () {
    final target = DeepLinkService.parseUri(
      Uri.parse('https://societyeats.vercel.app/s/seller-123'),
    );
    expect(target?.kind, DeepLinkKind.seller);
    expect(target?.id, 'seller-123');
  });

  test('parses /c/:campaignId paths', () {
    final target = DeepLinkService.parseUri(
      Uri.parse('https://societyeats.vercel.app/c/campaign-9'),
    );
    expect(target?.kind, DeepLinkKind.campaign);
    expect(target?.id, 'campaign-9');
  });

  test('parses /l/:listingId paths', () {
    final target = DeepLinkService.parseUri(
      Uri.parse('https://societyeats.vercel.app/l/listing-42'),
    );
    expect(target?.kind, DeepLinkKind.listing);
    expect(target?.id, 'listing-42');
  });

  test('parses hash routes', () {
    final target = DeepLinkService.parseUri(
      Uri.parse('https://societyeats.vercel.app/#/c/campaign-9'),
    );
    expect(target?.kind, DeepLinkKind.campaign);
    expect(target?.id, 'campaign-9');
  });

  test('parses query fallbacks', () {
    final seller = DeepLinkService.parseUri(
      Uri.parse('https://societyeats.vercel.app/?s=seller-1'),
    );
    expect(seller?.kind, DeepLinkKind.seller);
    expect(seller?.id, 'seller-1');

    final campaign = DeepLinkService.parseUri(
      Uri.parse('https://societyeats.vercel.app/?campaignId=c-2'),
    );
    expect(campaign?.kind, DeepLinkKind.campaign);
    expect(campaign?.id, 'c-2');

    final listing = DeepLinkService.parseUri(
      Uri.parse('https://societyeats.vercel.app/?listingId=l-3'),
    );
    expect(listing?.kind, DeepLinkKind.listing);
    expect(listing?.id, 'l-3');
  });

  test('ignores unrelated URLs', () {
    expect(
      DeepLinkService.parseUri(Uri.parse('https://societyeats.vercel.app/')),
      isNull,
    );
    expect(
      DeepLinkService.parseUri(
        Uri.parse('https://societyeats.vercel.app/home'),
      ),
      isNull,
    );
  });

  test('share URL helpers', () {
    expect(
      DeepLinkService.sellerShareUrl('abc'),
      endsWith('/s/abc'),
    );
    expect(
      DeepLinkService.campaignShareUrl('xyz'),
      endsWith('/c/xyz'),
    );
    expect(
      DeepLinkService.listingShareUrl('dish-1'),
      endsWith('/l/dish-1'),
    );
  });
}
