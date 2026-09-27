const recurringWeekdayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

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
