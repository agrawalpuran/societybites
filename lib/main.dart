import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/main_shell_screen.dart';
import 'screens/login_screen.dart';
import 'screens/society_selection_screen.dart';
import 'services/session_service.dart';
import 'services/push_notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  await PushNotificationService.init();

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
    final token = await SessionService.getToken();
    if (token == null) {
      return const LoginScreen();
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
