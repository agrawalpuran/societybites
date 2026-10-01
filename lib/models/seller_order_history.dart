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

/// How long a finished order keeps its place in Active. Mirrors
/// BuyerOrderVisibility.recentTerminalWindow so both sides of an order agree
/// on when it moves to Past.
const sellerRecentTerminalWindow = Duration(hours: 24);

DateTime? sellerPastEventAt({
  DateTime? completedAt,
  DateTime? cancelledAt,
  DateTime? rejectedAt,
  DateTime? createdAt,
}) {
  return completedAt ?? cancelledAt ?? rejectedAt ?? createdAt;
}

/// True while a terminal order is still inside its Active grace period.
/// Deliberately ignores createdAt: an order with no end timestamp has no
/// moment to count from, so it belongs in Past.
bool isSellerJustEnded({
  DateTime? completedAt,
  DateTime? cancelledAt,
  DateTime? rejectedAt,
  DateTime? now,
}) {
  final at = completedAt ?? cancelledAt ?? rejectedAt;
  if (at == null) return false;
  return (now ?? DateTime.now()).difference(at) < sellerRecentTerminalWindow;
}

bool isSellerRecentOpenOrder({
  required bool isTerminal,
  DateTime? createdAt,
  DateTime? completedAt,
  DateTime? cancelledAt,
  DateTime? rejectedAt,
  DateTime? now,
}) {
  if (isTerminal) {
    return isSellerJustEnded(
      completedAt: completedAt,
      cancelledAt: cancelledAt,
      rejectedAt: rejectedAt,
      now: now,
    );
  }
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
  if (isSellerJustEnded(
    completedAt: completedAt,
    cancelledAt: cancelledAt,
    rejectedAt: rejectedAt,
    now: now,
  )) {
    return false;
  }
  final at = sellerPastEventAt(
    completedAt: completedAt,
    cancelledAt: cancelledAt,
    rejectedAt: rejectedAt,
    createdAt: createdAt,
  );
  if (at == null) return false;
  return !at.isBefore(sellerRecentPastCutoff(now));
}

/// Terminal orders that have dropped out of Active and out of recent Past,
/// so they are only reachable from Older Orders.
bool isSellerOlderPastOrder({
  required bool isTerminal,
  DateTime? completedAt,
  DateTime? cancelledAt,
  DateTime? rejectedAt,
  DateTime? createdAt,
  DateTime? now,
}) {
  if (!isTerminal) return false;
  if (isSellerJustEnded(
    completedAt: completedAt,
    cancelledAt: cancelledAt,
    rejectedAt: rejectedAt,
    now: now,
  )) {
    return false;
  }
  return !isSellerRecentPastOrder(
    isTerminal: isTerminal,
    completedAt: completedAt,
    cancelledAt: cancelledAt,
    rejectedAt: rejectedAt,
    createdAt: createdAt,
    now: now,
  );
}
