import 'package:flutter/material.dart';

import '../models/data.dart';

const mixedAvailabilityCartMessage =
    "Available now and Made to order items can't go in the same cart. They follow different order steps — checkout one type first.";

const multipleMadeToOrderCartMessage =
    "This cart can hold one Made to order item at a time so the ready time stays clear. Checkout this one first, then order the other.";

/// Returns a buyer-facing message when [incoming] would mix order lifecycles.
String? cartAvailabilityConflict(List<CartItem> cart, FoodItem incoming) {
  if (cart.isEmpty) return null;
  if (cart.any((item) => item.food.id == incoming.id)) return null;
  final addingMadeToOrder = incoming.isMadeToOrder;
  final hasMadeToOrder = cart.any((item) => item.food.isMadeToOrder);
  final hasAvailableNow = cart.any((item) => !item.food.isMadeToOrder);
  if (addingMadeToOrder && hasAvailableNow) return mixedAvailabilityCartMessage;
  if (!addingMadeToOrder && hasMadeToOrder) return mixedAvailabilityCartMessage;
  if (addingMadeToOrder && hasMadeToOrder) {
    return multipleMadeToOrderCartMessage;
  }
  return null;
}

bool cartHasMixedAvailability(List<CartItem> cart) {
  final hasMadeToOrder = cart.any((item) => item.food.isMadeToOrder);
  final hasAvailableNow = cart.any((item) => !item.food.isMadeToOrder);
  return hasMadeToOrder && hasAvailableNow;
}

enum OneSellerCartAction { viewCart, continueBrowsing }

/// Empty cart and the same seller are allowed. A different seller is not.
bool canAddItemFromSeller(List<CartItem> cart, String sellerId) {
  if (cart.isEmpty) return true;
  return cart.first.food.sellerId == sellerId;
}

String cartSellerName(List<CartItem> cart) {
  if (cart.isEmpty) return 'this seller';
  final name = cart.first.food.sellerName.trim();
  return name.isEmpty ? 'this seller' : name;
}

/// Returns true when [sellerId] may be added or ordered.
/// A different seller shows the restriction sheet and does not change [cart].
Future<bool> confirmCartSellerAllowed(
  BuildContext context, {
  required List<CartItem> cart,
  required String sellerId,
  required String sellerName,
  List<CartItem>? alsoBlockedBy,
  Future<void> Function()? onViewCart,
}) async {
  final List<CartItem>? blocking;
  if (!canAddItemFromSeller(cart, sellerId)) {
    blocking = cart;
  } else if (alsoBlockedBy != null &&
      !identical(alsoBlockedBy, cart) &&
      !canAddItemFromSeller(alsoBlockedBy, sellerId)) {
    blocking = alsoBlockedBy;
  } else {
    blocking = null;
  }
  if (blocking == null) return true;

  final currentName = cartSellerName(blocking);
  final incoming = sellerName.trim().isEmpty ? 'this seller' : sellerName.trim();
  final action = await showModalBottomSheet<OneSellerCartAction>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetContext) {
      return SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD4DBD8),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Your cart already has items',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101617),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You already have items from $currentName in your cart.\n\n'
                'You can order from one seller at a time. Please complete or clear your current cart before ordering from $incoming.',
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF3A4644),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'One seller per cart',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8A9491),
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  key: const Key('one-seller-view-cart'),
                  onPressed: () => Navigator.pop(
                    sheetContext,
                    OneSellerCartAction.viewCart,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0E5A47),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'View Cart',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  key: const Key('one-seller-continue'),
                  onPressed: () => Navigator.pop(
                    sheetContext,
                    OneSellerCartAction.continueBrowsing,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF0E5A47),
                    side: const BorderSide(color: Color(0xFFD4E8DF)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    'Continue Browsing',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      );
    },
  );
  if (action == OneSellerCartAction.viewCart) {
    await onViewCart?.call();
  }
  return false;
}
