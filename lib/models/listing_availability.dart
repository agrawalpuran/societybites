const listingAvailabilityReadyNow = 'READY_NOW';
const listingAvailabilityMadeToOrder = 'MADE_TO_ORDER';

const preparationMinutesPerDay = 24 * 60;
const maxPreparationTimeMinutes = 10080;
const maxPreparationDays = maxPreparationTimeMinutes ~/ preparationMinutesPerDay;

int preparationMinutesFromDays(int days) => days * preparationMinutesPerDay;

int? preparationDaysFromMinutes(int? minutes) {
  if (minutes == null || minutes < preparationMinutesPerDay) return null;
  if (minutes % preparationMinutesPerDay != 0) return null;
  return minutes ~/ preparationMinutesPerDay;
}

String parseListingAvailabilityMode(dynamic value) {
  final raw = value?.toString().trim().toUpperCase();
  return raw == listingAvailabilityMadeToOrder
      ? listingAvailabilityMadeToOrder
      : listingAvailabilityReadyNow;
}

int? parsePreparationTimeMinutes(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String formatPreparationEstimate(int? minutes) {
  if (minutes == null || minutes <= 0) return '';
  final days = preparationDaysFromMinutes(minutes);
  if (days != null) {
    return days == 1
        ? 'Usually takes about 1 day'
        : 'Usually takes about $days days';
  }
  if (minutes < 60) return 'Usually takes about $minutes minutes';
  if (minutes == 60) return 'Usually takes about 1 hour';
  if (minutes % 60 == 0) {
    return 'Usually takes about ${minutes ~/ 60} hours';
  }
  final hours = minutes / 60.0;
  final label = hours == hours.roundToDouble()
      ? hours.toInt().toString()
      : hours.toStringAsFixed(1);
  return 'Usually takes about $label hours';
}

String formatPreparationShort(int? minutes) {
  if (minutes == null || minutes <= 0) return '';
  final days = preparationDaysFromMinutes(minutes);
  if (days != null) {
    return days == 1 ? '~1 day' : '~$days days';
  }
  if (minutes < 60) return '~$minutes min';
  if (minutes % 60 == 0) {
    final hours = minutes ~/ 60;
    return hours == 1 ? '~1 hr' : '~$hours hrs';
  }
  return '~${(minutes / 60).toStringAsFixed(1)} hrs';
}
