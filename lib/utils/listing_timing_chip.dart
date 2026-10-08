import '../models/data.dart';
import '../models/listing_availability.dart';

/// Third quick-info tile on listing detail (replaces misleading "15 min pickup").
class ListingTimingChipContent {
  const ListingTimingChipContent({
    required this.label,
    required this.value,
    required this.sub,
  });

  final String label;
  final String value;
  final String sub;
}

bool _hasSellingHoursSummary(FoodItem food) =>
    food.recurringHoursSummary.trim().isNotEmpty;

/// Ready-now listings store `availableAt` for auto-expiry (e.g. end of today),
/// not as a buyer-facing pickup clock time.
bool _treatAvailableAtAsBuyerDeadline(FoodItem food) {
  if (food.isMadeToOrder || food.isPreOrderCatalog || food.isPreOrder) {
    return false;
  }
  if (_hasSellingHoursSummary(food)) return false;
  if (!food.isMadeToOrder &&
      food.availabilityMode == listingAvailabilityReadyNow) {
    return false;
  }
  return food.availableAt != null;
}

String listingScheduleCaption(FoodItem food) {
  if (food.isMadeToOrder) {
    final short = formatPreparationShort(food.preparationTimeMinutes);
    if (short.isEmpty) return 'Made to order';
    return '$short prep';
  }
  if (_hasSellingHoursSummary(food)) {
    return food.recurringHoursSummary;
  }
  if (_treatAvailableAtAsBuyerDeadline(food)) {
    return 'Until ${food.pickupTime}';
  }
  return 'Ready now';
}

ListingTimingChipContent listingTimingChipFor(FoodItem food) {
  if (food.isMadeToOrder) {
    final short = formatPreparationShort(food.preparationTimeMinutes);
    final value = short.isEmpty
        ? 'Varies'
        : short.replaceFirst('~', '').trim();
    return ListingTimingChipContent(
      label: 'PREP TIME',
      value: value,
      sub: 'made after order',
    );
  }

  if (_hasSellingHoursSummary(food)) {
    return ListingTimingChipContent(
      label: 'HOURS',
      value: food.recurringHoursSummary.trim(),
      sub: 'order window',
    );
  }

  if (_treatAvailableAtAsBuyerDeadline(food)) {
    return ListingTimingChipContent(
      label: 'AVAILABLE',
      value: food.pickupTime,
      sub: 'until this time',
    );
  }

  return const ListingTimingChipContent(
    label: 'STATUS',
    value: 'Ready now',
    sub: 'pick up at seller',
  );
}
