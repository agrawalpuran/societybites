import 'package:flutter/material.dart';

import '../services/cart_controller.dart';

class CartHeaderButton extends StatelessWidget {
  const CartHeaderButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CartController.instance,
      builder: (context, _) {
        final itemCount = CartController.instance.itemCount;
        final badge = itemCount > 9 ? '9+' : '$itemCount';
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              key: const Key('home-cart-button'),
              tooltip: 'Cart',
              onPressed: () => CartController.instance.openCheckout(context),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 32),
              visualDensity: VisualDensity.compact,
              icon: Badge(
                isLabelVisible: itemCount > 0,
                label: Text(
                  badge,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                backgroundColor: const Color(0xFFE85D04),
                child: const Icon(
                  Icons.shopping_bag_outlined,
                  color: Color(0xFF0E5A47),
                  size: 22,
                ),
              ),
            ),
            const Text(
              'Cart',
              style: TextStyle(
                fontSize: 10,
                height: 1,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0E5A47),
              ),
            ),
          ],
        );
      },
    );
  }
}
