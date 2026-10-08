import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/kitchen_hours.dart';

void main() {
  test('unset kitchen hours stay open', () {
    expect(
      isKitchenOpen(now: DateTime.utc(2026, 10, 4, 3)),
      isTrue,
    );
  });

  test('daytime window uses India time and closes at the close minute', () {
    expect(
      isKitchenOpen(
        opensAt: '09:00',
        closesAt: '21:00',
        now: DateTime.utc(2026, 10, 4, 4),
      ),
      isTrue,
    );
    expect(
      isKitchenOpen(
        opensAt: '09:00',
        closesAt: '21:00',
        now: DateTime.utc(2026, 10, 4, 3),
      ),
      isFalse,
    );
    expect(
      isKitchenOpen(
        opensAt: '09:00',
        closesAt: '21:00',
        now: DateTime.utc(2026, 10, 4, 15, 30),
      ),
      isFalse,
    );
  });

  test('overnight window stays open past midnight', () {
    expect(
      isKitchenOpen(
        opensAt: '18:00',
        closesAt: '02:00',
        now: DateTime.utc(2026, 10, 4, 13),
      ),
      isTrue,
    );
    expect(
      isKitchenOpen(
        opensAt: '18:00',
        closesAt: '02:00',
        now: DateTime.utc(2026, 10, 4, 20),
      ),
      isTrue,
    );
    expect(
      isKitchenOpen(
        opensAt: '18:00',
        closesAt: '02:00',
        now: DateTime.utc(2026, 10, 4, 10),
      ),
      isFalse,
    );
  });

  test('subtitle describes the saved window', () {
    expect(kitchenHoursSubtitle(null, null), 'Always open');
    expect(
      kitchenHoursSubtitle('09:00', '21:00'),
      'Open 9:00 AM · Close 9:00 PM',
    );
    expect(
      kitchenHoursSubtitle(defaultKitchenOpensAt, defaultKitchenClosesAt),
      'Open 8:00 AM · Close 8:00 PM',
    );
  });
}
