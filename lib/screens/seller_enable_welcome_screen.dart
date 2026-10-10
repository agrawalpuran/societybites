import 'package:flutter/material.dart';

import '../services/seller_onboarding.dart';
import '../web/web_breakpoints.dart';
import '../web/web_page_frame.dart';

/// Shown once after a buyer completes first-time seller enable and lands on
/// My Kitchen — same full-screen pattern as [PreOrderConfirmationScreen].
class SellerEnableWelcomeScreen extends StatelessWidget {
  const SellerEnableWelcomeScreen({super.key});

  static const _green = Color(0xFF0E5A47);
  static const _ink = Color(0xFF101617);
  static const _muted = Color(0xFF6A7774);
  static const _border = Color(0xFFEAEFED);

  /// Pushes the welcome screen. Returns `true` if the seller chose Add listing.
  static Future<bool> show(BuildContext context) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const SellerEnableWelcomeScreen(),
      ),
    );
    return result == true;
  }

  @override
  Widget build(BuildContext context) {
    final web = useWebMarketplaceLayout(context);
    return Scaffold(
      key: const Key('seller-kitchen-welcome'),
      backgroundColor: const Color(0xFFF8FAF9),
      body: SafeArea(
        child: centerOnWeb(
          context,
          SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, web ? 32 : 24, 20, 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: Color(0xFFE8F5EE),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check_rounded,
                        color: _green,
                        size: 42,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      SellerOnboarding.sellerKitchenWelcomeTitle,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: _ink,
                        fontSize: web ? 30 : 26,
                        fontWeight: FontWeight.w900,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _border),
                      ),
                      child: Text(
                        SellerOnboarding.sellerKitchenWelcomeMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _muted,
                          fontSize: 15,
                          height: 1.45,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.add_rounded, size: 22),
                        label: const Text(
                          'Add listing',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        style: TextButton.styleFrom(
                          foregroundColor: _ink,
                        ),
                        child: const Text(
                          'Got it',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          maxWidth: 720,
        ),
      ),
    );
  }
}
