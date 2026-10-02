import 'dart:async';

/// Pull-to-refresh already has the list on screen. The iOS wheel should
/// acknowledge the tug and dismiss, while the reload updates the list
/// when the response arrives.
class PullRefreshGate {
  PullRefreshGate({Duration? dismissAfter})
    : dismissAfter = dismissAfter ?? const Duration(milliseconds: 350);

  final Duration dismissAfter;
  Future<void>? _pending;

  Future<void> run(Future<void> Function() reload) {
    if (_pending == null) {
      _pending = reload().catchError((Object _, StackTrace _) {}).whenComplete(
        () {
          _pending = null;
        },
      );
    }
    return Future<void>.delayed(dismissAfter);
  }
}
