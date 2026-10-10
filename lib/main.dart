import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/main_shell_screen.dart';
import 'screens/guest_landing_screen.dart';
import 'screens/login_screen.dart';
import 'screens/society_selection_screen.dart';
import 'theme/app_theme.dart';
import 'web/web_marketplace_states.dart';
import 'widgets/app_header.dart' show kAppDisplayName;
import 'widgets/mobile_startup_frame.dart';
import 'services/api_service.dart';
import 'services/auth_config.dart';
import 'services/session_service.dart';
import 'services/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  ApiService.onSessionInvalidated = () {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = PushNotificationService.navigatorKey.currentState;
      if (navigator == null) return;
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(
          builder: (_) =>
              kIsWeb ? const MainShellScreen() : const LoginScreen(),
        ),
        (_) => false,
      );
    });
  };

  runApp(const MyApp());

  unawaited(PushNotificationService.init());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: kAppDisplayName,
      debugShowCheckedModeBanner: false,
      theme: societyBitesTheme(),
      navigatorKey: PushNotificationService.navigatorKey,
      home: const AuthGate(),
    );
  }
}

/// Logged-out start. Web opens the marketplace. Mobile keeps the landing page.
Widget signedOutStartScreen() {
  if (kIsWeb) return const MainShellScreen();
  return const GuestLandingScreen();
}

/// Normal auth/session routing. Throws are handled by [AuthGate].
Future<Widget> resolveAuthStartScreen() async {
  final warmTokens = SessionService.warmAuthCache();

  if (AuthConfig.usesTwoFactor) {
    final sessionProvider = await SessionService.getAuthProvider();
    if (sessionProvider != '2factor') {
      // Remove stale Firebase-session identity before the one-time migration
      // login. Firebase SDK/FCM initialization remains intact.
      await SessionService.clear();
      return signedOutStartScreen();
    }

    final refreshToken = await SessionService.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return signedOutStartScreen();
    }

    if (!await ApiService.restoreTwoFactorSession()) {
      return signedOutStartScreen();
    }
  } else {
    final token = await SessionService.getToken();
    if (token == null || token.isEmpty) {
      return signedOutStartScreen();
    }
  }

  if (await SessionService.isOnboarded()) {
    await warmTokens;
    return const MainShellScreen();
  }

  final userId = await SessionService.getUserId();
  if (userId != null) {
    return const SocietySelectionScreen();
  }

  return signedOutStartScreen();
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, this.resolveStartScreen});

  /// Test seam. Production uses [resolveAuthStartScreen].
  final Future<Widget> Function()? resolveStartScreen;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late final Future<Widget> _startup;

  @override
  void initState() {
    super.initState();
    unawaited(SessionService.warmAuthCache());
    _startup = _safeResolve();
  }

  Future<Widget> _safeResolve() async {
    try {
      final resolve = widget.resolveStartScreen ?? resolveAuthStartScreen;
      return await resolve();
    } catch (error, stack) {
      debugPrint('[auth] startup resolve failed: $error\n$stack');
      return signedOutStartScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _startup,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          debugPrint('[auth] startup future error: ${snapshot.error}');
          return signedOutStartScreen();
        }
        if (!snapshot.hasData) {
          if (kIsWeb) return const WebStartupFrame();
          return const MobileStartupFrame();
        }

        return snapshot.data!;
      },
    );
  }
}
