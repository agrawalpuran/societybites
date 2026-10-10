import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/models/selling_reach.dart';
import 'package:societybites/services/home_feed_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('save and load round-trip for a society feed', () async {
    const reach = SellingReach(
      cityKey: 'bengaluru',
      nearbyRadiusKm: 3,
      extendedRadiusKm: 8,
    );
    await HomeFeedCache.save(
      societyId: 'society-a',
      listingMaps: [
        {
          'id': 'listing-1',
          'name': 'Samosa',
          'sellerId': 'seller-1',
          'sellerName': 'Anita',
          'price': 20,
          'status': 'active',
        },
      ],
      cityReach: reach,
    );

    final loaded = await HomeFeedCache.load('society-a');
    expect(loaded, isNotNull);
    expect(loaded!.listingMaps.single['name'], 'Samosa');
    expect(loaded.cityReach.nearbyRadiusKm, 3);
    expect(loaded.cityReach.extendedRadiusKm, 8);
    expect(await HomeFeedCache.load('society-b'), isNull);
  });

  test('retainOnly keeps the active society cache', () async {
    await HomeFeedCache.save(
      societyId: 'old-society',
      listingMaps: [
        {
          'id': 'listing-old',
          'name': 'Old',
          'sellerId': 'seller-1',
          'sellerName': 'Anita',
          'price': 10,
          'status': 'active',
        },
      ],
      cityReach: const SellingReach(),
    );
    await HomeFeedCache.save(
      societyId: 'new-society',
      listingMaps: [
        {
          'id': 'listing-new',
          'name': 'New',
          'sellerId': 'seller-2',
          'sellerName': 'Ravi',
          'price': 15,
          'status': 'active',
        },
      ],
      cityReach: const SellingReach(),
    );

    await HomeFeedCache.retainOnly('new-society');

    expect(await HomeFeedCache.load('old-society'), isNull);
    expect(await HomeFeedCache.load('new-society'), isNotNull);
  });

  test('load drops snapshots older than maxSnapshotAge', () async {
    final prefs = await SharedPreferences.getInstance();
    final staleAt = DateTime.now()
        .toUtc()
        .subtract(HomeFeedCache.maxSnapshotAge + const Duration(hours: 1));
    await prefs.setString(
      'home_feed_cache_v1_stale-society',
      '{"societyId":"stale-society","savedAt":"${staleAt.toIso8601String()}",'
      '"listings":[{"id":"l1","name":"Old","sellerId":"s1","sellerName":"A",'
      '"price":10,"status":"active"}],"cityReach":{"cityKey":"","nearbyRadiusKm":null,"extendedRadiusKm":null}}',
    );

    expect(await HomeFeedCache.load('stale-society'), isNull);
    expect(prefs.getString('home_feed_cache_v1_stale-society'), isNull);
  });
}
