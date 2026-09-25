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

/// One cart = one seller. Returns true if the buyer wants to replace the cart.
Future<bool> confirmReplaceSellerCart(
  BuildContext context, {
  required String currentSellerName,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Your cart contains items from another seller.'),
      content: Text(
        'Start a new cart with this seller? Items from $currentSellerName will be removed.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF0E5A47)),
          child: const Text('Start New Cart'),
        ),
      ],
    ),
  );
  return result == true;
}
