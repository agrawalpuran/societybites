import 'package:flutter/material.dart';

import '../models/data.dart';
import '../screens/checkout_screen.dart';
import '../screens/login_screen.dart';
import 'session_service.dart';

/// Shared in-memory cart for buyer tabs. Not persisted; no extra API calls.
class CartController extends ChangeNotifier {
  CartController._();
  static final CartController instance = CartController._();

  final List<CartItem> items = [];

  /// Home reloads listings after a successful checkout.
  VoidCallback? onOrderPlaced;

  /// Main shell switches to the buyer Orders tab after checkout.
  VoidCallback? onShowOrdersAfterPlace;

  int get itemCount =>
      items.fold<int>(0, (sum, item) => sum + item.quantity);

  double get total =>
      items.fold<double>(0, (sum, item) => sum + item.total);

  void notify() => notifyListeners();

  void clear() {
    if (items.isEmpty) return;
    items.clear();
    notifyListeners();
  }

  /// Cart is already placed. Clear local cart and notify Home / MainShell.
  void handlePlacedOrder() {
    clear();
    onOrderPlaced?.call();
    onShowOrdersAfterPlace?.call();
  }

  /// After checkout from a listing, storefront, or pre-order, drop those
  /// screens so the buyer is back on the shell Orders tab.
  void finishPlacedOrder(BuildContext context) {
    handlePlacedOrder();
    if (!context.mounted) return;
    final navigator = Navigator.of(context);
    if (!navigator.canPop()) return;
    navigator.popUntil((route) => route.isFirst);
  }

  Future<bool> openCheckout(BuildContext context) async {
    final signedIn = await SessionService.isSignedIn();
    if (!context.mounted) return false;
    if (!signedIn) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return false;
    }
    final placed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CheckoutScreen(cartItems: List.from(items)),
      ),
    );
    if (placed == true) {
      handlePlacedOrder();
      return true;
    }
    return false;
  }
}
