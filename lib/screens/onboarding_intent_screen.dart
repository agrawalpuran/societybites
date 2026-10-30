import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/session_service.dart';
import '../web/web_breakpoints.dart';
import '../web/web_page_frame.dart';
import '../widgets/app_header.dart';
import 'login_screen.dart';
import 'society_selection_screen.dart';

/// Post-OTP choice for users who still need society / flat onboarding.
class OnboardingIntentScreen extends StatefulWidget {
  const OnboardingIntentScreen({super.key});

  @override
  State<OnboardingIntentScreen> createState() => _OnboardingIntentScreenState();
}

class _OnboardingIntentScreenState extends State<OnboardingIntentScreen> {
  bool _switchingNumber = false;

  Future<void> _choose(String intent) async {
    if (_switchingNumber) return;
    await SessionService.setOnboardingIntent(intent);
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const SocietySelectionScreen()),
    );
  }

  Future<void> _useDifferentNumber() async {
    if (_switchingNumber) return;
    setState(() => _switchingNumber = true);

    final authProvider = await SessionService.getAuthProvider();
    final refreshToken = await SessionService.getRefreshToken();
    final headers = await ApiService.captureAuthHeaders();
    await SessionService.clearOnboardingIntent();
    await SessionService.clear();
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );

    unawaited(
      ApiService.endSessionRemotely(
        headers: headers,
        refreshToken: refreshToken,
      ),
    );
    if (authProvider == 'firebase') {
      unawaited(FirebaseAuth.instance.signOut());
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!useWebMarketplaceLayout(context))
              const AppHeader(showCart: false),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('onboarding-use-different-number'),
                onPressed: _switchingNumber ? null : _useDifferentNumber,
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 16),
                label: const Text('Use a different number'),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF0E5A47),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'What brings you here?',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Color(0xFF101617),
                height: 1.15,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Choose how you want to start. You can always do both later.',
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: Color(0xFF6A7774),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 24),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: _IntentCard(
                      key: const Key('onboarding-intent-order'),
                      icon: Icons.shopping_bag_outlined,
                      title: 'Order food',
                      subtitle: 'Homemade food near you',
                      onTap: _switchingNumber
                          ? null
                          : () => _choose(SessionService.onboardingIntentBuyer),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _IntentCard(
                      key: const Key('onboarding-intent-sell'),
                      icon: Icons.storefront_outlined,
                      title: 'Sell food',
                      subtitle: 'List dishes for neighbors',
                      onTap: _switchingNumber
                          ? null
                          : () =>
                              _choose(SessionService.onboardingIntentSeller),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Sellers can still order. Buyers can start selling later from Profile.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: Color(0xFF8A9491),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );

    if (useWebMarketplaceLayout(context)) {
      return centerOnWeb(
        context,
        Scaffold(
          backgroundColor: const Color(0xFFF8FAF9),
          body: body,
        ),
      );
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      body: body,
    );
  }
}

class _IntentCard extends StatelessWidget {
  const _IntentCard({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE3E8E4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5EE),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: const Color(0xFF0E5A47), size: 22),
              ),
              const SizedBox(height: 12),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101617),
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  color: Color(0xFF6A7774),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
