import 'dart:async';

import 'package:flutter/foundation.dart';

/// Debug-only preload trail. Stripped from concern in release via [kDebugMode].
void debugPreloadLog(String message) {
  if (kDebugMode) {
    debugPrint(message);
  }
}

/// Sequential background preload after Home is usable.
///
/// Mounts Orders, waits until that first load settles, then mounts Dashboard.
/// Profile is not auto-mounted — it has no extra work worth competing with Home.
/// Safe to call [onHomeInitialLoadSuccess] more than once; only the first runs.
class HomeFirstPreload {
  HomeFirstPreload({
    required this.onMountOrders,
    required this.onMountDashboard,
    this.log = debugPreloadLog,
  });

  final VoidCallback onMountOrders;
  final VoidCallback onMountDashboard;
  final void Function(String message) log;

  bool _started = false;
  bool _disposed = false;
  bool _ordersSettled = false;
  bool _dashboardSettled = false;
  Completer<void>? _ordersGate;
  Completer<void>? _dashboardGate;

  bool get hasStarted => _started;
  bool get isDisposed => _disposed;

  void onHomeInitialLoadSuccess() {
    if (_disposed || _started) return;
    _started = true;
    log('BACKGROUND PRELOAD START');
    unawaited(_run());
  }

  Future<void> _run() async {
    await _preloadOrders();
    if (_disposed) return;
    await _preloadDashboard();
  }

  Future<void> _preloadOrders() async {
    if (_disposed) return;
    log('ORDERS PRELOAD START');
    _ordersGate = Completer<void>();
    onMountOrders();
    if (!_ordersSettled && !_disposed) {
      await _ordersGate!.future;
    }
    if (_disposed) return;
    log('ORDERS PRELOAD COMPLETE');
  }

  Future<void> _preloadDashboard() async {
    if (_disposed) return;
    log('DASHBOARD PRELOAD START');
    _dashboardGate = Completer<void>();
    onMountDashboard();
    if (!_dashboardSettled && !_disposed) {
      await _dashboardGate!.future;
    }
    if (_disposed) return;
    log('DASHBOARD PRELOAD COMPLETE');
  }

  void onOrdersInitialLoadSettled() {
    if (_disposed) return;
    _ordersSettled = true;
    final gate = _ordersGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  void onDashboardInitialLoadSettled() {
    if (_disposed) return;
    _dashboardSettled = true;
    final gate = _dashboardGate;
    if (gate != null && !gate.isCompleted) {
      gate.complete();
    }
  }

  void dispose() {
    _disposed = true;
    final orders = _ordersGate;
    if (orders != null && !orders.isCompleted) {
      orders.complete();
    }
    final dashboard = _dashboardGate;
    if (dashboard != null && !dashboard.isCompleted) {
      dashboard.complete();
    }
  }
}
