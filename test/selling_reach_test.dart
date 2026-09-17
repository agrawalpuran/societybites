import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/selling_reach.dart';

void main() {
  test('parses sellingReachLevel including default MY_SOCIETY', () {
    expect(parseSellingReachLevel('MY_SOCIETY'), SellingReachLevel.mySociety);
    expect(parseSellingReachLevel('nearby'), SellingReachLevel.nearby);
    expect(parseSellingReachLevel('EXTENDED'), SellingReachLevel.extended);
    expect(parseSellingReachLevel(null), SellingReachLevel.mySociety);
    expect(parseSellingReachLevel(''), SellingReachLevel.mySociety);
    expect(SellingReachLevel.mySociety.apiValue, 'MY_SOCIETY');
  });

  test('parses city reach configuration from /auth/me', () {
    final me = {
      'sellingReachLevel': 'MY_SOCIETY',
      'sellingReach': {
        'cityKey': 'bengaluru',
        'nearbyRadiusKm': 5,
        'extendedRadiusKm': 10,
      },
    };

    expect(parseSellingReachLevel(me['sellingReachLevel']), SellingReachLevel.mySociety);
    final reach = SellingReach.fromAuthMe(me);
    expect(reach.cityKey, 'bengaluru');
    expect(reach.nearbyRadiusKm, 5);
    expect(reach.extendedRadiusKm, 10);
  });

  test('parses NEARBY and EXTENDED independently', () {
    expect(parseSellingReachLevel('NEARBY').title, 'Nearby');
    expect(parseSellingReachLevel('EXTENDED').title, 'Extended');
    expect(SellingReachLevel.nearby.apiValue, 'NEARBY');
    expect(SellingReachLevel.extended.apiValue, 'EXTENDED');
  });

  test('displays configured radius and disables missing levels', () {
    final configured = SellingReach.fromAuthMe({
      'sellingReach': {
        'cityKey': 'bengaluru',
        'nearbyRadiusKm': 5,
        'extendedRadiusKm': 10,
      },
    });
    expect(configured.nearbyAvailable, isTrue);
    expect(configured.extendedAvailable, isTrue);
    expect(configured.optionSubtitleFor(SellingReachLevel.nearby), 'Buyers within 5 km');
    expect(configured.optionSubtitleFor(SellingReachLevel.extended), 'Buyers within 10 km');

    final nearbyOnly = const SellingReach(cityKey: 'bengaluru', nearbyRadiusKm: 5);
    expect(nearbyOnly.isSelectable(SellingReachLevel.nearby), isTrue);
    expect(nearbyOnly.isSelectable(SellingReachLevel.extended), isFalse);

    final missing = SellingReach.fromAuthMe({
      'sellingReach': {
        'cityKey': 'bengaluru',
        'nearbyRadiusKm': null,
        'extendedRadiusKm': null,
      },
    });
    expect(missing.nearbyAvailable, isFalse);
    expect(missing.extendedAvailable, isFalse);
    expect(missing.isSelectable(SellingReachLevel.mySociety), isTrue);
    expect(
      missing.optionSubtitleFor(SellingReachLevel.nearby),
      'Nearby selling is not available in your city yet.',
    );
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
