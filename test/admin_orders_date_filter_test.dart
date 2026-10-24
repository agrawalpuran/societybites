import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/screens/admin/admin_orders_screen.dart';

void main() {
  test('today covers the full local day', () {
    final now = DateTime(2026, 10, 23, 20, 11);
    final range = adminOrdersQueryRange(preset: 'today', now: now);
    expect(range.from, DateTime(2026, 10, 23));
    expect(range.to, DateTime(2026, 10, 23, 23, 59, 59, 999));
  });

  test('yesterday is the previous local day', () {
    final range = adminOrdersQueryRange(
      preset: 'yesterday',
      now: DateTime(2026, 10, 24, 8, 11),
    );
    expect(range.from, DateTime(2026, 10, 23));
    expect(range.to!.day, 23);
    expect(range.to!.hour, 23);
  });

  test('last 7 days includes today and six days before', () {
    final range = adminOrdersQueryRange(
      preset: 'week',
      now: DateTime(2026, 10, 24, 12),
    );
    expect(range.from, DateTime(2026, 10, 18));
    expect(range.to, DateTime(2026, 10, 24, 23, 59, 59, 999));
  });

  test('all dates sends no range', () {
    final range = adminOrdersQueryRange(
      preset: 'all',
      now: DateTime(2026, 10, 24),
    );
    expect(range.from, isNull);
    expect(range.to, isNull);
  });

  test('custom range includes both selected days', () {
    final range = adminOrdersQueryRange(
      preset: 'custom',
      now: DateTime(2026, 10, 24),
      customFrom: DateTime(2026, 10, 20, 15),
      customTo: DateTime(2026, 10, 22, 1),
    );
    expect(range.from, DateTime(2026, 10, 20));
    expect(range.to, DateTime(2026, 10, 22, 23, 59, 59, 999));
  });
}
