import 'package:flutter/material.dart';

import '../screens/login_screen.dart';

Future<void> showGuestOrderAuthDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Ready to order?'),
      content: const Text(
        'Sign in or join SocietyBites to add items to your cart and place an order.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Not now'),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context);
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
