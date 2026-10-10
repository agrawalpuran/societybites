import 'package:flutter/material.dart';

import 'app_header.dart';

/// Branded session bootstrap — not a feed skeleton.
class MobileStartupFrame extends StatelessWidget {
  const MobileStartupFrame({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('mobile-startup-frame'),
      backgroundColor: const Color(0xFFF8FAF9),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const AppHeader(showCart: false),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        kAppDisplayName,
                        style: const TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0E5A47),
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Homemade food in your society',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.35,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF6A7774),
                        ),
                      ),
                      const SizedBox(height: 28),
                      SizedBox(
                        width: 160,
                        child: LinearProgressIndicator(
                          minHeight: 3,
                          borderRadius: BorderRadius.circular(4),
                          backgroundColor: const Color(0xFFEAEFED),
                          color: const Color(0xFF0E5A47),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
