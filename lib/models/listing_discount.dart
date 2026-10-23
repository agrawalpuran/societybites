const int listingDiscountMinPercent = 1;
const int listingDiscountMaxPercent = 90;

const String listingDiscountToggleLabel = 'Offer a discount';
const String listingDiscountUnboundedHint =
    'Leave both dates blank for no date restriction.';
const String listingDiscountVariantGroupHint =
    'This discount will apply to all sizes of this product.';
const String listingDiscountPercentRangeError =
    'Enter a whole-number percentage from 1 to 90.';
const String listingDiscountDateRangeError =
    'The end date cannot be earlier than the start date.';

/// Matches backend `money()`: two decimal places, half-up via round-to-nearest.
double listingDiscountMoney(num value) {
  return (value * 100).round() / 100;
}

double listingDiscountEffectivePrice(num regularPrice, num percent) {
  return listingDiscountMoney(
    listingDiscountMoney(regularPrice) * (1 - percent / 100),
  );
}

DateTime listingDiscountCalendarDate(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

DateTime listingDiscountStartInstant(DateTime calendarDate) {
  final day = listingDiscountCalendarDate(calendarDate);
  return DateTime(day.year, day.month, day.day);
}

DateTime listingDiscountEndInstant(DateTime calendarDate) {
  final day = listingDiscountCalendarDate(calendarDate);
  return DateTime(day.year, day.month, day.day, 23, 59, 59, 999);
}

bool listingDiscountPercentIsAllowed(int? percent) {
  return percent != null &&
      percent >= listingDiscountMinPercent &&
      percent <= listingDiscountMaxPercent;
}

String? listingDiscountValidationError({
  required bool enabled,
  int? percent,
  DateTime? startsAt,
  DateTime? endsAt,
}) {
  if (!enabled) return null;
  if (!listingDiscountPercentIsAllowed(percent)) {
    return listingDiscountPercentRangeError;
  }
  if (startsAt != null &&
      endsAt != null &&
      listingDiscountCalendarDate(endsAt)
          .isBefore(listingDiscountCalendarDate(startsAt))) {
    return listingDiscountDateRangeError;
  }
  return null;
}

/// Fields accepted by POST /listings and PATCH /listings/:id.
///
/// Disabled updates send only `discountEnabled: false` so the backend keeps
/// stored percent/dates. Enabled writes always include dates (null = unbounded).
Map<String, dynamic> listingDiscountFieldsForApi({
  required bool enabled,
  int? percent,
  DateTime? startsAt,
  DateTime? endsAt,
}) {
  if (!enabled) {
    return {'discountEnabled': false};
  }
  return {
    'discountEnabled': true,
    'discountPercent': percent,
    'discountStartsAt': startsAt == null
        ? null
        : listingDiscountStartInstant(startsAt).toUtc().toIso8601String(),
    'discountEndsAt': endsAt == null
        ? null
        : listingDiscountEndInstant(endsAt).toUtc().toIso8601String(),
  };
}

/// Buyer-facing regular vs charged unit price. Never cheaper than regular.
class ListingDisplayPrice {
  const ListingDisplayPrice({
    required this.regularPrice,
    required this.chargedPrice,
    required this.saleActive,
    this.discountPercent,
  });

  final double regularPrice;
  final double chargedPrice;
  final bool saleActive;
  final double? discountPercent;
}

/// Uses backend `effectivePrice` only when `discountActive` and the value is a
/// finite amount strictly below regular price. Does not recompute from percent.
ListingDisplayPrice resolveListingDisplayPrice({
  required num regularPrice,
  bool discountActive = false,
  double? effectivePrice,
  double? discountPercent,
}) {
  final regular = listingDiscountMoney(regularPrice);
  if (!discountActive) {
    return ListingDisplayPrice(
      regularPrice: regular,
      chargedPrice: regular,
      saleActive: false,
    );
  }
  if (effectivePrice == null ||
      !effectivePrice.isFinite ||
      effectivePrice <= 0) {
    return ListingDisplayPrice(
      regularPrice: regular,
      chargedPrice: regular,
      saleActive: false,
    );
  }
  final charged = listingDiscountMoney(effectivePrice);
  if (charged >= regular) {
    return ListingDisplayPrice(
      regularPrice: regular,
      chargedPrice: regular,
      saleActive: false,
    );
  }
  return ListingDisplayPrice(
    regularPrice: regular,
    chargedPrice: charged,
    saleActive: true,
    discountPercent: discountPercent,
  );
}

double? optionalListingDiscountAmount(Object? value) {
  if (value == null) return null;
  if (value is num) {
    return value.isFinite ? value.toDouble() : null;
  }
  final parsed = double.tryParse(value.toString().trim());
  if (parsed == null || !parsed.isFinite) return null;
  return parsed;
}

DateTime? optionalListingDiscountDate(Object? value) {
  if (value == null) return null;
  final raw = value.toString().trim();
  if (raw.isEmpty || raw == 'null') return null;
  return DateTime.tryParse(raw);
}
