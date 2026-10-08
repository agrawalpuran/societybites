import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/models/data.dart';
import 'package:societybites/models/listing_availability.dart';
import 'package:societybites/utils/listing_timing_chip.dart';

FoodItem _food({
  String mode = listingAvailabilityReadyNow,
  int? preparationTimeMinutes,
  DateTime? availableAt,
  bool recurring = false,
}) {
  return FoodItem(
    id: 'l1',
    name: 'Test',
    sellerId: 's1',
    sellerName: 'Seller',
    block: 'Block C',
    flatNumber: '3062',
    price: 100,
    rating: 0,
    pickupTime: availableAt == null ? '15 min' : '7:00 PM',
    description: '',
    icon: Icons.restaurant,
    bgColor: const Color(0xFFE8F5EE),
    availabilityMode: mode,
    preparationTimeMinutes: preparationTimeMinutes,
    availableAt: availableAt,
    recurringEnabled: recurring,
    recurringStartMinute: recurring ? 9 * 60 : null,
    recurringEndMinute: recurring ? 18 * 60 : null,
  );
}

void main() {
  test('ready now shows Ready now not address', () {
    final chip = listingTimingChipFor(_food());
    expect(chip.label, 'STATUS');
    expect(chip.value, 'Ready now');
    expect(chip.sub, 'pick up at seller');
    expect(listingScheduleCaption(_food()), 'Ready now');
  });

  test('ready now hides auto-expiry availableAt', () {
    final endOfDay = DateTime(2026, 10, 8, 18, 29);
    final chip = listingTimingChipFor(
      _food(availableAt: endOfDay),
    );
    expect(chip.label, 'STATUS');
    expect(chip.value, 'Ready now');
    expect(listingScheduleCaption(_food(availableAt: endOfDay)), 'Ready now');
  });

  test('same-day hours use hours summary not availableAt clock', () {
    final food = FoodItem(
      id: 'l2',
      name: 'Idli',
      sellerId: 's1',
      sellerName: 'Seller',
      block: 'Block A',
      flatNumber: '1111',
      price: 55,
      rating: 0,
      pickupTime: '6:29 PM',
      description: '',
      icon: Icons.restaurant,
      bgColor: const Color(0xFFE8F5EE),
      availableAt: DateTime(2026, 10, 8, 18, 29),
      recurringHoursSummary: '7:00 AM – 11:00 AM',
    );
    final chip = listingTimingChipFor(food);
    expect(chip.label, 'HOURS');
    expect(chip.value, '7:00 AM – 11:00 AM');
  });

  test('made to order shows prep time', () {
    final chip = listingTimingChipFor(
      _food(
        mode: listingAvailabilityMadeToOrder,
        preparationTimeMinutes: 180,
      ),
    );
    expect(chip.label, 'PREP TIME');
    expect(chip.value, '3 hrs');
    expect(chip.sub, 'made after order');
    expect(
      listingScheduleCaption(
        _food(
          mode: listingAvailabilityMadeToOrder,
          preparationTimeMinutes: 180,
        ),
      ),
      '~3 hrs prep',
    );
  });
}
