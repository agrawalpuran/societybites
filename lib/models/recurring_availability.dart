const recurringWeekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const recurringWeekdayShortLabels = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

bool parseRecurringEnabled(dynamic value) => value == true || value == 'true';

List<int> parseRecurringWeekdays(dynamic value) {
  if (value is! List) return const [];
  return value
      .map((item) => item is num ? item.toInt() : int.tryParse(item.toString()))
      .whereType<int>()
      .where((day) => day >= 1 && day <= 7)
      .toSet()
      .toList()
    ..sort();
}

int? parseOptionalInt(dynamic value) {
  if (value == null || value == '') return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

String formatRecurringClock(int minuteOfDay) {
  final safe = minuteOfDay.clamp(0, 1439);
  final hour24 = safe ~/ 60;
  final minute = safe % 60;
  final ampm = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '$hour12:${minute.toString().padLeft(2, '0')} $ampm';
}

int timeOfDayToMinute(int hour, int minute) => hour * 60 + minute;

String formatRecurringWeekdaysSummary(List<int> weekdays) {
  final days = [...weekdays]
      .where((n) => n >= 1 && n <= 7)
      .toSet()
      .toList()
    ..sort();
  if (days.isEmpty) return '';
  if (days.length == 7) return 'Every day';
  final labels = days.map((n) => recurringWeekdayShortLabels[n - 1]).toList();
  final consecutive =
      days.length > 1 &&
      days.asMap().entries.every((e) => e.key == 0 || e.value == days[e.key - 1] + 1);
  if (consecutive && days.length >= 3) {
    return '${labels.first}–${labels.last}';
  }
  return labels.join(', ');
}

String formatRecurringHoursSummary(int? startMinute, int? endMinute) {
  if (startMinute == null || endMinute == null) return '';
  return '${formatRecurringClock(startMinute)} – ${formatRecurringClock(endMinute)}';
}

String formatRecurringWindowLabel({
  required List<int> weekdays,
  int? startMinute,
  int? endMinute,
  String scheduleSummary = '',
  String hoursSummary = '',
}) {
  final schedule = scheduleSummary.trim().isNotEmpty
      ? scheduleSummary.trim()
      : formatRecurringWeekdaysSummary(weekdays);
  final hours = hoursSummary.trim().isNotEmpty
      ? hoursSummary.trim()
      : formatRecurringHoursSummary(startMinute, endMinute);
  return [schedule, hours].where((part) => part.isNotEmpty).join(' · ');
}
