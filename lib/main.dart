import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/main_shell_screen.dart';
import 'screens/login_screen.dart';
import 'screens/society_selection_screen.dart';
import 'services/api_service.dart';
import 'services/auth_config.dart';
import 'services/session_service.dart';
import 'services/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  await PushNotificationService.init();

  ApiService.onSessionInvalidated = () {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = PushNotificationService.navigatorKey.currentState;
      if (navigator == null) return;
      navigator.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    });
  };

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SocietyBites',
      debugShowCheckedModeBanner: false,
      navigatorKey: PushNotificationService.navigatorKey,
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  Future<Widget> _resolveStartScreen() async {
    if (AuthConfig.usesTwoFactor) {
      final sessionProvider = await SessionService.getAuthProvider();
      if (sessionProvider != '2factor') {
        // Remove stale Firebase-session identity before the one-time migration
        // login. Firebase SDK/FCM initialization remains intact.
        await SessionService.clear();
        return const LoginScreen();
      }

      final refreshToken = await SessionService.getRefreshToken();
      if (refreshToken == null || refreshToken.isEmpty) {
        return const LoginScreen();
      }

      if (!await ApiService.restoreTwoFactorSession()) {
        return const LoginScreen();
      }
    } else {
      final token = await SessionService.getToken();
      if (token == null || token.isEmpty) {
        return const LoginScreen();
      }
    }

    if (await SessionService.isOnboarded()) {
      return const MainShellScreen();
    }

    final userId = await SessionService.getUserId();
    if (userId != null) {
      return const SocietySelectionScreen();
    }

    return const LoginScreen();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _resolveStartScreen(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Color(0xFFF8FAF9),
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
            ),
          );
        }

        return snapshot.data!;
      },
    );
  }
}
