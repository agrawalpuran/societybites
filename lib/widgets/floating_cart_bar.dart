import 'package:flutter/material.dart';

import '../services/cart_controller.dart';
import 'preorder_widgets.dart';

/// Bottom checkout chip on Home. Header cart stays; this is a second entry.
class FloatingCartBar extends StatelessWidget {
  const FloatingCartBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CartController.instance,
      builder: (context, _) {
        final cart = CartController.instance;
        if (cart.itemCount == 0) return const SizedBox.shrink();
        return FloatingActionButton.extended(
          key: const Key('home-floating-cart'),
          onPressed: () => cart.openCheckout(context),
          backgroundColor: const Color(0xFF0E5A47),
          foregroundColor: Colors.white,
          icon: const Icon(
            Icons.shopping_bag_rounded,
            size: 20,
            color: Colors.white,
          ),
          label: Text(
            '${cart.itemCount} items  •  ${formatMoney(cart.total)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        );
      },
    );
  }
}
