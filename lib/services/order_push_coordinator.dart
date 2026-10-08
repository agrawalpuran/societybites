import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/data.dart';

/// Hint from FCM data so the Orders UI can update before GET /orders returns.
class OrderPushHint {
  const OrderPushHint({
    required this.orderId,
    this.status,
    this.paymentStatus,
  });

  final String orderId;
  final String? status;
  final String? paymentStatus;

  Map<String, dynamic> toJson() => {
    'orderId': orderId,
    if (status != null) 'status': status,
    if (paymentStatus != null) 'paymentStatus': paymentStatus,
  };

  factory OrderPushHint.fromJson(Map<String, dynamic> json) {
    return OrderPushHint(
      orderId: json['orderId']?.toString() ?? '',
      status: _nonEmpty(json['status']),
      paymentStatus: _nonEmpty(json['paymentStatus']),
    );
  }

  static OrderPushHint? fromMessageData(Map<String, dynamic> data) {
    final orderId = data['orderId']?.toString().trim() ?? '';
    if (orderId.isEmpty) return null;

    final status = _nonEmpty(data['status']) ?? _statusFromNotificationType(data);
    final paymentStatus =
        _nonEmpty(data['paymentStatus']) ??
        _paymentFromNotificationType(data);

    if (status == null && paymentStatus == null) return null;
    return OrderPushHint(
      orderId: orderId,
      status: status,
      paymentStatus: paymentStatus,
    );
  }

  static OrderPushHint? fromRemoteMessage(RemoteMessage message) {
    return fromMessageData(message.data);
  }

  static String? _nonEmpty(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static String? _statusFromNotificationType(Map<String, dynamic> data) {
    switch (data['notificationType']?.toString()) {
      case 'order_created':
        return 'pending';
      case 'order_accepted':
        return 'accepted';
      case 'order_ready':
        return 'ready';
      case 'order_completed':
        return 'completed';
      case 'order_cancelled':
        return 'cancelled';
      case 'order_rejected':
        return 'rejected';
      default:
        return null;
    }
  }

  static String? _paymentFromNotificationType(Map<String, dynamic> data) {
    switch (data['notificationType']?.toString()) {
      case 'buyer_marked_paid':
        return 'buyer_marked_paid';
      case 'payment_confirmed':
        return 'seller_confirmed';
      default:
        return null;
    }
  }
}

int orderStatusStepFor(String status) {
  switch (status) {
    case 'pending':
      return 0;
    case 'accepted':
    case 'preparing':
      return 1;
    case 'ready':
    case 'picked_up':
      return 2;
    case 'completed':
      return 3;
    case 'cancelled':
    case 'rejected':
      return -1;
    default:
      return 0;
  }
}

int _orderStatusRank(String status) {
  switch (status) {
    case 'pending':
      return 0;
    case 'accepted':
    case 'preparing':
      return 1;
    case 'ready':
    case 'picked_up':
      return 2;
    case 'completed':
      return 3;
    default:
      return -2;
  }
}

int _paymentStatusRank(String status) {
  switch (status) {
    case 'pending':
      return 0;
    case 'buyer_marked_paid':
      return 1;
    case 'seller_confirmed':
      return 2;
    case 'paid':
      return 3;
    default:
      return 0;
  }
}

bool _shouldApplyStatus(String current, String next) {
  if (current == next) return false;
  const terminal = {'cancelled', 'rejected', 'completed'};
  if (terminal.contains(next)) return true;
  return _orderStatusRank(next) > _orderStatusRank(current);
}

Order applyOrderPushHint(Order order, OrderPushHint hint) {
  if (order.id != hint.orderId) return order;

  var status = order.status;
  var statusStep = order.statusStep;
  var paymentStatus = order.paymentStatus;
  var completedAt = order.completedAt;
  var cancelledAt = order.cancelledAt;
  var rejectedAt = order.rejectedAt;

  final nextStatus = hint.status;
  if (nextStatus != null && _shouldApplyStatus(status, nextStatus)) {
    status = nextStatus;
    statusStep = orderStatusStepFor(nextStatus);
    final now = DateTime.now();
    if (nextStatus == 'completed') {
      completedAt = completedAt ?? now;
    } else if (nextStatus == 'cancelled') {
      cancelledAt = cancelledAt ?? now;
    } else if (nextStatus == 'rejected') {
      rejectedAt = rejectedAt ?? now;
    }
  }

  final nextPayment = hint.paymentStatus;
  if (nextPayment != null &&
      _paymentStatusRank(nextPayment) > _paymentStatusRank(paymentStatus)) {
    paymentStatus = nextPayment;
  }

  if (status == order.status &&
      statusStep == order.statusStep &&
      paymentStatus == order.paymentStatus &&
      completedAt == order.completedAt &&
      cancelledAt == order.cancelledAt &&
      rejectedAt == order.rejectedAt) {
    return order;
  }

  return Order(
    id: order.id,
    orderId: order.orderId,
    items: order.items,
    date: order.date,
    status: status,
    statusStep: statusStep,
    orderTotal: order.orderTotal,
    subtotal: order.subtotal,
    communityFee: order.communityFee,
    deliveryCharge: order.deliveryCharge,
    couponCode: order.couponCode,
    couponDiscount: order.couponDiscount,
    type: order.type,
    campaignId: order.campaignId,
    fulfilmentMethod: order.fulfilmentMethod,
    fulfilmentNotes: order.fulfilmentNotes,
    fulfilmentAt: order.fulfilmentAt,
    campaignTitle: order.campaignTitle,
    campaignOrderCutoffAt: order.campaignOrderCutoffAt,
    paymentMethod: order.paymentMethod,
    paymentStatus: paymentStatus,
    hasReview: order.hasReview,
    rejectReason: order.rejectReason,
    rejectedAt: rejectedAt,
    cancelReason: order.cancelReason,
    refundDue: order.refundDue,
    sellerCanDecline: order.sellerCanDecline,
    completedAt: completedAt,
    cancelledAt: cancelledAt,
    expectedReadyAt: order.expectedReadyAt,
    requestedReadyAt: order.requestedReadyAt,
    createdAt: order.createdAt,
    buyerName: order.buyerName,
    buyerPhone: order.buyerPhone,
    buyerFlatNumber: order.buyerFlatNumber,
    buyerBlock: order.buyerBlock,
    buyerSocietyName: order.buyerSocietyName,
    sellerSocietyName: order.sellerSocietyName,
    distanceKm: order.distanceKm,
    unreadMessageCount: order.unreadMessageCount,
  );
}

List<Order> applyOrderPushHints(List<Order> orders, List<OrderPushHint> hints) {
  if (hints.isEmpty) return orders;
  return orders
      .map(
        (order) => hints.fold(
          order,
          (current, hint) => applyOrderPushHint(current, hint),
        ),
      )
      .toList();
}

/// Merges push hints from foreground/background delivery and applies them in UI.
class OrderPushCoordinator {
  static const _prefsKey = 'order_push_hints_v1';

  static final Map<String, OrderPushHint> _pending = {};

  static List<OrderPushHint> get pendingHints => _pending.values.toList();

  /// Seller (or buyer) action before GET /orders catches up — same path as FCM hints.
  static void stageHint(OrderPushHint hint) {
    if (hint.orderId.isEmpty) return;
    if (hint.status == null && hint.paymentStatus == null) return;
    _pending[hint.orderId] = _merge(_pending[hint.orderId], hint);
    unawaited(_persist());
  }

  static void dropHint(String orderId) {
    if (orderId.isEmpty) return;
    _pending.remove(orderId);
    unawaited(_persist());
  }

  /// Keep forward progress from [local] when a refresh returns stale status/payment.
  static Order reconcileServerOrder(Order local, Order server) {
    var merged = Order.mergePreservingDetails(local, server);
    if (_orderStatusRank(local.status) > _orderStatusRank(merged.status)) {
      merged = applyOrderPushHint(
        merged,
        OrderPushHint(orderId: merged.id, status: local.status),
      );
    }
    if (_paymentStatusRank(local.paymentStatus) >
        _paymentStatusRank(merged.paymentStatus)) {
      merged = applyOrderPushHint(
        merged,
        OrderPushHint(orderId: merged.id, paymentStatus: local.paymentStatus),
      );
    }
    return merged;
  }

  static Future<void> recordFromMessage(RemoteMessage message) async {
    final hint = OrderPushHint.fromRemoteMessage(message);
    if (hint == null) return;
    _pending[hint.orderId] = _merge(_pending[hint.orderId], hint);
    unawaited(_persist());
  }

  /// Foreground pushes already merged in memory; resume/background needs prefs first.
  static Future<void> ensureHydrated() async {
    if (_pending.isNotEmpty) {
      unawaited(_mergeFromPrefs());
      return;
    }
    await _mergeFromPrefs();
  }

  static Future<void> hydrateFromStore() => ensureHydrated();

  static Future<void> _mergeFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        final hint = OrderPushHint.fromJson(Map<String, dynamic>.from(value));
        if (hint.orderId.isEmpty) continue;
        _pending[hint.orderId] = _merge(_pending[hint.orderId], hint);
      }
    } catch (_) {}
    await prefs.remove(_prefsKey);
  }

  static void clearApplied(Iterable<OrderPushHint> hints) {
    for (final hint in hints) {
      _pending.remove(hint.orderId);
    }
    unawaited(_persist());
  }

  /// Drop hints only once the in-memory order has caught up (avoids stale GET /orders).
  static void clearHintsReconciled(Iterable<Order> orders) {
    final byId = {for (final order in orders) order.id: order};
    for (final hint in List<OrderPushHint>.from(_pending.values)) {
      final order = byId[hint.orderId];
      if (order == null) continue;
      final statusOk =
          hint.status == null ||
          _orderStatusRank(order.status) >= _orderStatusRank(hint.status!);
      final paymentOk =
          hint.paymentStatus == null ||
          _paymentStatusRank(order.paymentStatus) >=
              _paymentStatusRank(hint.paymentStatus!);
      if (statusOk && paymentOk) {
        _pending.remove(hint.orderId);
      }
    }
    unawaited(_persist());
  }

  static OrderPushHint _merge(OrderPushHint? prior, OrderPushHint next) {
    if (prior == null) return next;
    return OrderPushHint(
      orderId: next.orderId,
      status: next.status ?? prior.status,
      paymentStatus: next.paymentStatus ?? prior.paymentStatus,
    );
  }

  static Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (_pending.isEmpty) {
      await prefs.remove(_prefsKey);
      return;
    }
    final encoded = jsonEncode({
      for (final e in _pending.entries) e.key: e.value.toJson(),
    });
    await prefs.setString(_prefsKey, encoded);
  }
}
