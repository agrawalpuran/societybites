class SellerOrderListPage {
  const SellerOrderListPage({
    required this.orders,
    this.hasMore = false,
    this.hasOlder = false,
    this.pendingCount = 0,
  });

  final List<Map<String, dynamic>> orders;
  final bool hasMore;
  final bool hasOlder;
  final int pendingCount;
}

const sellerRecentPastDays = 7;

/// IST calendar start of the first day in the recent-past window (today + 6 prior days).
DateTime sellerRecentPastCutoff([DateTime? now]) {
  final instant = now ?? DateTime.now();
  final ist = instant.toUtc().add(const Duration(hours: 5, minutes: 30));
  final from = DateTime.utc(ist.year, ist.month, ist.day).subtract(
    const Duration(days: sellerRecentPastDays - 1),
  );
  final y = from.year.toString().padLeft(4, '0');
  final m = from.month.toString().padLeft(2, '0');
  final d = from.day.toString().padLeft(2, '0');
  return DateTime.parse('$y-$m-${d}T00:00:00.000+05:30');
}

DateTime? sellerPastEventAt({
  DateTime? completedAt,
  DateTime? cancelledAt,
  DateTime? rejectedAt,
  DateTime? createdAt,
}) {
  return completedAt ?? cancelledAt ?? rejectedAt ?? createdAt;
}

bool isSellerRecentOpenOrder({
  required bool isTerminal,
  DateTime? createdAt,
  DateTime? now,
}) {
  if (isTerminal) return false;
  if (createdAt == null) return true;
  return !createdAt.isBefore(sellerRecentPastCutoff(now));
}

bool isSellerRecentPastOrder({
  required bool isTerminal,
  DateTime? completedAt,
  DateTime? cancelledAt,
  DateTime? rejectedAt,
  DateTime? createdAt,
  DateTime? now,
}) {
  if (!isTerminal) return false;
  final at = sellerPastEventAt(
    completedAt: completedAt,
    cancelledAt: cancelledAt,
    rejectedAt: rejectedAt,
    createdAt: createdAt,
  );
  if (at == null) return false;
  return !at.isBefore(sellerRecentPastCutoff(now));
}
