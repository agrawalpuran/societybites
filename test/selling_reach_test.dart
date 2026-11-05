import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/selling_reach.dart';

void main() {
  test('parses sellingReachLevel including default MY_SOCIETY', () {
    expect(parseSellingReachLevel('MY_SOCIETY'), SellingReachLevel.mySociety);
    expect(parseSellingReachLevel('nearby'), SellingReachLevel.nearby);
    expect(parseSellingReachLevel('EXTENDED'), SellingReachLevel.extended);
    expect(parseSellingReachLevel('BEYOND_SOCIETY'), SellingReachLevel.beyondSociety);
    expect(parseSellingReachLevel(null), SellingReachLevel.mySociety);
    expect(parseSellingReachLevel(''), SellingReachLevel.mySociety);
    expect(SellingReachLevel.mySociety.apiValue, 'MY_SOCIETY');
    expect(SellingReachLevel.beyondSociety.apiValue, 'BEYOND_SOCIETY');
  });

  test('parses city reach configuration from /auth/me', () {
    final me = {
      'sellingReachLevel': 'MY_SOCIETY',
      'sellingReach': {
        'cityKey': 'bengaluru',
        'nearbyRadiusKm': 5,
        'extendedRadiusKm': 10,
        'maxSellerRadiusKm': 10,
      },
    };

    expect(parseSellingReachLevel(me['sellingReachLevel']), SellingReachLevel.mySociety);
    final reach = SellingReach.fromAuthMe(me);
    expect(reach.cityKey, 'bengaluru');
    expect(reach.nearbyRadiusKm, 5);
    expect(reach.extendedRadiusKm, 10);
    expect(reach.maxRadiusKm, 10);
  });

  test('parses NEARBY and EXTENDED independently', () {
    expect(parseSellingReachLevel('NEARBY'), SellingReachLevel.nearby);
    expect(parseSellingReachLevel('EXTENDED'), SellingReachLevel.extended);
    expect(SellingReachLevel.nearby.apiValue, 'NEARBY');
    expect(SellingReachLevel.extended.apiValue, 'EXTENDED');
    expect(SellingReachLevel.nearby.isBeyondSociety, isTrue);
    expect(SellingReachLevel.extended.isBeyondSociety, isTrue);
  });

  test('exposes city availability and preference summaries', () {
    final configured = SellingReach.fromAuthMe({
      'sellingReach': {
        'cityKey': 'bengaluru',
        'nearbyRadiusKm': 5,
        'extendedRadiusKm': 10,
        'maxSellerRadiusKm': 10,
      },
    });
    expect(configured.beyondSocietyAvailable, isTrue);
    expect(configured.extendedAvailable, isTrue);
    expect(
      const SellerReachPreference(mySocietyOnly: true, radiusKm: 5)
          .summary(configured),
      'Visible to buyers in your society',
    );
    expect(
      const SellerReachPreference(mySocietyOnly: false, radiusKm: 5)
          .summary(configured),
      'Buyers in your society and within 5 km',
    );

    final missing = SellingReach.fromAuthMe({
      'sellingReach': {
        'cityKey': null,
        'nearbyRadiusKm': null,
        'extendedRadiusKm': null,
      },
    });
    expect(missing.beyondSocietyAvailable, isFalse);
    expect(missing.extendedAvailable, isFalse);
  });

  test('null radius handling when city config is missing', () {
    final reach = SellingReach.fromAuthMe({
      'sellingReachLevel': 'MY_SOCIETY',
      'sellingReach': {
        'cityKey': 'bengaluru',
        'nearbyRadiusKm': null,
        'extendedRadiusKm': null,
      },
    });

    expect(reach.cityKey, 'bengaluru');
    expect(reach.nearbyRadiusKm, isNull);
    expect(reach.extendedRadiusKm, isNull);

    final empty = SellingReach.fromJson(null);
    expect(empty.nearbyRadiusKm, isNull);
    expect(empty.extendedRadiusKm, isNull);
  });
}
