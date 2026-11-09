import 'package:flutter/material.dart';

import '../navigation/kitchen_site_navigation.dart';
import '../screens/login_screen.dart';
import '../screens/society_selection_screen.dart';
import '../services/session_service.dart';

/// True when the buyer must sign in before adding to cart.
Future<bool> guestOrderNeedsLoginPrompt() async {
  if (await SessionService.isOnboarded()) return false;
  final refresh = await SessionService.getRefreshToken();
  final token = await SessionService.getToken();
  final hasSession = (token != null && token.isNotEmpty) ||
      (refresh != null && refresh.isNotEmpty);
  return !hasSession;
}

/// Blocks guest add-to-cart until login or society join is complete.
Future<bool> handleGuestKitchenAddToCart(BuildContext context) async {
  if (await SessionService.isOnboarded()) return true;
  if (await guestOrderNeedsLoginPrompt()) {
    await showGuestOrderAuthDialog(context);
    return false;
  }
  if (!context.mounted) return false;
  await Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => const SocietySelectionScreen()),
  );
  return false;
}

Future<void> showGuestOrderAuthDialog(BuildContext context) {
  final onKitchenSite = KitchenSiteNavigation.isKitchenSiteContext;
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Ready to order?'),
      content: Text(
        onKitchenSite
            ? 'Sign in or join your society to order from this kitchen.'
            : 'Sign in or join SocietyBites to add items to your cart and place an order.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Not now'),
        ),
        TextButton(
          onPressed: () async {
            Navigator.pop(context);
            final slug = KitchenSiteNavigation.activeKitchenSlug();
            if (slug != null) {
              await KitchenSiteNavigation.holdKitchenSlug(slug);
            }
            if (!context.mounted) return;
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
          },
          style: TextButton.styleFrom(foregroundColor: const Color(0xFF0E5A47)),
          child: const Text('Sign In / Join Society'),
        ),
      ],
    ),
  );
}
