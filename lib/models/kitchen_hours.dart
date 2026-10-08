import 'package:flutter/material.dart';

const kitchenClosedMessage = 'Kitchen closed';

/// Default window for new sellers (first-time setup); not the same as “always open”.
const defaultKitchenOpensAt = '08:00';
const defaultKitchenClosesAt = '20:00';

const _istOffset = Duration(hours: 5, minutes: 30);

int? clockToMinutes(String? value) {
  if (value == null) return null;
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value.trim());
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}

int istMinutes(DateTime instant) {
  final shifted = instant.toUtc().add(_istOffset);
  return shifted.hour * 60 + shifted.minute;
}

/// Unset hours stay open. A close time earlier than open stays open past midnight.
bool isKitchenOpen({
  String? opensAt,
  String? closesAt,
  DateTime? now,
}) {
  final open = clockToMinutes(opensAt);
  final close = clockToMinutes(closesAt);
  if (open == null || close == null) return true;
  if (open == close) return false;
  final current = istMinutes(now ?? DateTime.now());
  if (open < close) return current >= open && current < close;
  return current >= open || current < close;
}

String formatKitchenClock(String value) {
  final minutes = clockToMinutes(value);
  if (minutes == null) return value;
  final hour24 = minutes ~/ 60;
  final minute = minutes % 60;
  final period = hour24 >= 12 ? 'PM' : 'AM';
  final hour12 = hour24 % 12 == 0 ? 12 : hour24 % 12;
  return '$hour12:${minute.toString().padLeft(2, '0')} $period';
}

String kitchenHoursSubtitle(String? opensAt, String? closesAt) {
  final open = clockToMinutes(opensAt);
  final close = clockToMinutes(closesAt);
  if (open == null || close == null || opensAt == null || closesAt == null) {
    return 'Always open';
  }
  return 'Open ${formatKitchenClock(opensAt)} · Close ${formatKitchenClock(closesAt)}';
}

String clockFromTimeOfDay(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

TimeOfDay timeOfDayFromClock(String? value, TimeOfDay fallback) {
  final minutes = clockToMinutes(value);
  if (minutes == null) return fallback;
  return TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
}

void showKitchenClosedMessage(BuildContext context) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: const Text(kitchenClosedMessage),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      backgroundColor: const Color(0xFFD94F4F),
    ),
  );
}
