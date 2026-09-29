import 'package:flutter/material.dart';

import '../services/cart_controller.dart';
import '../widgets/preorder_widgets.dart';
import 'web_breakpoints.dart';

/// Desktop checkout entry. Uses the existing cart and checkout path.
class WebCartDock extends StatelessWidget {
  const WebCartDock({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: CartController.instance,
      builder: (context, _) {
        final cart = CartController.instance;
        if (cart.itemCount == 0) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Align(
            alignment: Alignment.center,
            child: Material(
              color: webGreen,
              elevation: 6,
              shadowColor: const Color(0x330E5A47),
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                key: const Key('web-cart-dock'),
                borderRadius: BorderRadius.circular(16),
                onTap: () => cart.openCheckout(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.shopping_bag_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        cart.itemCount == 1
                            ? '1 item'
                            : '${cart.itemCount} items',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatMoney(cart.total),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 14),
                      const Text(
                        'View cart',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
