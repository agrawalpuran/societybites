import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/data.dart';
import '../services/api_service.dart';
import '../services/order_push_coordinator.dart';
import '../services/push_notification_service.dart';

/// Full-screen accept/reject UI for new seller orders (Swiggy-style).
class SellerIncomingOrderAlert extends StatefulWidget {
  const SellerIncomingOrderAlert({
    super.key,
    required this.orderId,
    this.orderNumber,
    this.onResolved,
    this.onOrderLoaded,
  });

  final String orderId;
  final String? orderNumber;
  final VoidCallback? onResolved;
  final ValueChanged<Order>? onOrderLoaded;

  /// Show once per orderId. Returns when dismissed.
  static Future<void> presentIfNeeded(
    BuildContext context, {
    required String orderId,
    String? orderNumber,
    ValueChanged<Order>? onOrderLoaded,
  }) async {
    final id = orderId.trim();
    if (id.isEmpty) return;
    if (_openOrderIds.contains(id)) return;
    _openOrderIds.add(id);
    unawaited(PushNotificationService.setIncomingOrderWakeScreen(true));
    try {
      await showGeneralDialog<void>(
        context: context,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.72),
        transitionDuration: const Duration(milliseconds: 220),
        pageBuilder: (ctx, anim, secondary) {
          return SellerIncomingOrderAlert(
            orderId: id,
            orderNumber: orderNumber,
            onOrderLoaded: onOrderLoaded,
            onResolved: () {
              if (Navigator.of(ctx).canPop()) {
                Navigator.of(ctx).pop();
              }
            },
          );
        },
        transitionBuilder: (ctx, anim, secondary, child) {
          final curved = CurvedAnimation(
            parent: anim,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
              child: child,
            ),
          );
        },
      );
    } finally {
      _openOrderIds.remove(id);
      unawaited(PushNotificationService.setIncomingOrderWakeScreen(false));
    }
  }

  static final Set<String> _openOrderIds = {};

  @override
  State<SellerIncomingOrderAlert> createState() =>
      _SellerIncomingOrderAlertState();
}

class _SellerIncomingOrderAlertState extends State<SellerIncomingOrderAlert> {
  Order? _order;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _soundOn = true;

  /// `pending` → Accept/Reject. `accepted` → auto-confirmed ready-now order.
  _IncomingMode _mode = _IncomingMode.loading;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(HapticFeedback.heavyImpact());
  }

  Future<void> _load() async {
    try {
      final json = await ApiService.getOrderById(widget.orderId);
      if (!mounted) return;
      final order = Order.fromJson(json);
      _IncomingMode mode;
      if (order.status == 'pending') {
        mode = _IncomingMode.needsAcceptance;
      } else if (order.status == 'accepted') {
        mode = _IncomingMode.autoAccepted;
      } else if (order.isTerminal) {
        mode = _IncomingMode.alreadyClosed;
      } else {
        mode = _IncomingMode.inProgress;
      }
      setState(() {
        _order = order;
        _mode = mode;
        _loading = false;
      });
      widget.onOrderLoaded?.call(order);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this order';
        _loading = false;
        _mode = _IncomingMode.error;
      });
    }
  }

  Future<void> _accept() async {
    final order = _order;
    if (order == null || _busy) return;
    setState(() => _busy = true);
    OrderPushCoordinator.stageHint(
      OrderPushHint(orderId: order.id, status: 'accepted'),
    );
    try {
      await ApiService.advanceOrderStatus(
        orderId: order.id,
        currentStatus: order.status,
        nextStatus: 'accepted',
      );
      if (!mounted) return;
      widget.onResolved?.call();
    } catch (e) {
      OrderPushCoordinator.dropHint(order.id);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.userFacingError(e))),
      );
    }
  }

  /// Auto-accepted orders are already `accepted`. `preparing` is retired —
  /// Kitchen's next step is Mark Ready. This button only acknowledges.
  void _acknowledgePreparing() {
    if (_busy) return;
    widget.onResolved?.call();
  }

  void _muteSound() {
    if (!_soundOn) return;
    setState(() => _soundOn = false);
    unawaited(PushNotificationService.stopIncomingOrderSound());
  }

  Future<void> _reject() async {
    final order = _order;
    if (order == null || _busy) return;
    if (order.status != 'pending' && order.status != 'accepted') return;
    setState(() => _busy = true);
    OrderPushCoordinator.stageHint(
      OrderPushHint(orderId: order.id, status: 'rejected'),
    );
    try {
      await ApiService.rejectOrder(
        orderId: order.id,
        reason: 'Too many orders',
      );
      if (!mounted) return;
      widget.onResolved?.call();
    } catch (e) {
      OrderPushCoordinator.dropHint(order.id);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.userFacingError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final number = widget.orderNumber?.trim().isNotEmpty == true
        ? widget.orderNumber!.trim()
        : (order?.orderId ?? '…');
    final itemLine = order == null
        ? null
        : order.items.map((i) => '${i.quantity}× ${i.food.name}').join(', ');

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: const Color(0xFF0A1210),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  _soundOn
                      ? Icons.notifications_active_rounded
                      : Icons.notifications_off_rounded,
                  color: _soundOn
                      ? const Color(0xFFFFB020)
                      : const Color(0xFF8A9491),
                  size: 52,
                ),
                if (_soundOn) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _muteSound,
                    icon: const Icon(
                      Icons.volume_off_rounded,
                      color: Color(0xFFFFB020),
                    ),
                    label: const Text(
                      'Stop sound',
                      style: TextStyle(
                        color: Color(0xFFFFB020),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text(
                  _titleForMode(_mode),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Order $number',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFB8C4C0),
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_subtitleForMode(_mode) != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _subtitleForMode(_mode)!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFF8A9491),
                      fontSize: 14,
                      height: 1.35,
                    ),
                  ),
                ],
                const Spacer(),
                if (_loading) ...[
                  const Center(
                    child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
                  ),
                  const Spacer(),
                ] else if (_error != null) ...[
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFFF8A80)),
                  ),
                  const SizedBox(height: 20),
                  _primaryButton(
                    label: 'Dismiss',
                    onPressed: widget.onResolved,
                  ),
                ] else ...[
                  if (itemLine != null && itemLine.isNotEmpty) ...[
                    Text(
                      itemLine,
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (order != null)
                    Text(
                      '₹${order.total.toStringAsFixed(0)}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF7DFFB2),
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  const Spacer(),
                  if (_mode == _IncomingMode.needsAcceptance) ...[
                    _primaryButton(
                      label: 'Accept',
                      onPressed: _busy ? null : _accept,
                      busy: _busy,
                    ),
                    const SizedBox(height: 12),
                    _outlineButton(
                      label: 'Reject',
                      onPressed: _busy ? null : _reject,
                    ),
                  ] else if (_mode == _IncomingMode.autoAccepted) ...[
                    _primaryButton(
                      label: 'Start preparing',
                      onPressed: _busy ? null : _acknowledgePreparing,
                    ),
                    const SizedBox(height: 12),
                    _outlineButton(
                      label: "Can't fulfil",
                      onPressed: _busy ? null : _reject,
                    ),
                  ] else ...[
                    _primaryButton(
                      label: 'Open in Kitchen',
                      onPressed: widget.onResolved,
                    ),
                  ],
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: _busy ? null : widget.onResolved,
                    child: const Text(
                      'Decide later in Kitchen',
                      style: TextStyle(
                        color: Color(0xFF8A9491),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _titleForMode(_IncomingMode mode) {
    switch (mode) {
      case _IncomingMode.needsAcceptance:
        return 'New order';
      case _IncomingMode.autoAccepted:
        return 'New order';
      case _IncomingMode.inProgress:
        return 'Order update';
      case _IncomingMode.alreadyClosed:
        return 'Order closed';
      case _IncomingMode.error:
        return 'New order';
      case _IncomingMode.loading:
        return 'New order';
    }
  }

  String? _subtitleForMode(_IncomingMode mode) {
    switch (mode) {
      case _IncomingMode.autoAccepted:
        return 'Ready-now items are confirmed automatically. Start preparing when you can.';
      case _IncomingMode.inProgress:
        return 'This order is already being handled in your kitchen.';
      case _IncomingMode.alreadyClosed:
        return 'This order is no longer open.';
      default:
        return null;
    }
  }

  Widget _primaryButton({
    required String label,
    VoidCallback? onPressed,
    bool busy = false,
  }) {
    return SizedBox(
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0E5A47),
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xFF2A3A36),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
    );
  }

  Widget _outlineButton({
    required String label,
    VoidCallback? onPressed,
  }) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFFFF8A80),
          side: const BorderSide(color: Color(0xFF5A3A3A)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

enum _IncomingMode {
  loading,
  needsAcceptance,
  autoAccepted,
  inProgress,
  alreadyClosed,
  error,
}
