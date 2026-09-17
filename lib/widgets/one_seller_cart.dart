import 'package:flutter/material.dart';

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
