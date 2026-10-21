import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/data.dart';
import '../services/api_service.dart';
import '../services/order_push_coordinator.dart';

/// Full-screen accept/reject sheet for new seller orders (Swiggy-style).
class SellerIncomingOrderAlert extends StatefulWidget {
  const SellerIncomingOrderAlert({
    super.key,
    required this.orderId,
    this.orderNumber,
    this.onResolved,
  });

  final String orderId;
  final String? orderNumber;
  final VoidCallback? onResolved;

  /// Show once per pending orderId. Returns when dismissed.
  static Future<void> presentIfNeeded(
    BuildContext context, {
    required String orderId,
    String? orderNumber,
  }) async {
    final id = orderId.trim();
    if (id.isEmpty) return;
    if (_openOrderIds.contains(id)) return;
    _openOrderIds.add(id);
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
            onResolved: () {
              if (Navigator.of(ctx).canPop()) {
                Navigator.of(ctx).pop();
              }
            },
          );
        },
        transitionBuilder: (ctx, anim, secondary, child) {
          final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
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

  @override
  void initState() {
    super.initState();
    unawaited(_load());
    unawaited(HapticFeedback.heavyImpact());
    SystemSound.play(SystemSoundType.alert);
  }

  Future<void> _load() async {
    try {
      final json = await ApiService.getOrderById(widget.orderId);
      if (!mounted) return;
      final order = Order.fromJson(json);
      if (order.status != 'pending') {
        widget.onResolved?.call();
        return;
      }
      setState(() {
        _order = order;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this order';
        _loading = false;
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
    } catch (_) {
      OrderPushCoordinator.dropHint(order.id);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not accept order')),
      );
    }
  }

  Future<void> _reject() async {
    final order = _order;
    if (order == null || _busy) return;
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
    } catch (_) {
      OrderPushCoordinator.dropHint(order.id);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not reject order')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final number =
        widget.orderNumber?.trim().isNotEmpty == true
            ? widget.orderNumber!.trim()
            : (order?.orderId ?? '…');
    final itemLine = order == null
        ? null
        : order.items
            .map((i) => '${i.quantity}× ${i.food.name}')
            .join(', ');

    return SafeArea(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Material(
            color: const Color(0xFF101617),
            borderRadius: BorderRadius.circular(28),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(
                      Icons.notifications_active_rounded,
                      color: Color(0xFFFFB020),
                      size: 44,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'New order',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
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
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (_loading) ...[
                      const SizedBox(height: 28),
                      const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF0E5A47),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ] else if (_error != null) ...[
                      const SizedBox(height: 20),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFFFF8A80)),
                      ),
                      const SizedBox(height: 20),
                      TextButton(
                        onPressed: widget.onResolved,
                        child: const Text('Dismiss'),
                      ),
                    ] else ...[
                      if (itemLine != null && itemLine.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          itemLine,
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ],
                      if (order != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          '₹${order.total.toStringAsFixed(0)}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF7DFFB2),
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      SizedBox(
                        height: 54,
                        child: ElevatedButton(
                          onPressed: _busy ? null : _accept,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0E5A47),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: const Color(0xFF2A3A36),
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: _busy
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Accept',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _busy ? null : _reject,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFF8A80),
                            side: const BorderSide(color: Color(0xFF5A3A3A)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'Reject',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
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
        ),
      ),
    );
  }
}
