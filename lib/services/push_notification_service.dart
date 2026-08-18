import 'dart:io' show Platform;

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'api_service.dart';
import '../screens/main_shell_screen.dart';

/// Top-level background handler (must be a top-level or static function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Data is delivered; UI refresh happens on resume / tap.
}

/// Optional soft FCM registration + foreground/tap handling.
/// Never blocks login or orders if permission is denied.
class PushNotificationService {
  PushNotificationService._();

  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static VoidCallback? onForegroundOrderUpdate;

  static const _sellerTypes = {
    'order_created',
    'buyer_marked_paid',
    'order_cancelled',
    'order_picked_up',
    'order_completed',
  };

  static bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<void> init() async {
    if (!_supported) return;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    FirebaseMessaging.onMessage.listen((message) {
      onForegroundOrderUpdate?.call();
    });

    FirebaseMessaging.onMessageOpenedApp.listen(_handleOpen);

    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _handleOpen(initial));
    }
  }

  /// Soft permission + token register. Safe to call repeatedly.
  static Future<void> registerIfPossible() async {
    if (!_supported) return;

    try {
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      final token = await messaging.getToken();
      if (token == null || token.isEmpty) return;

      final platform = Platform.isIOS ? 'ios' : 'android';
      await ApiService.registerDeviceToken(token, platform: platform);

      messaging.onTokenRefresh.listen((newToken) async {
        try {
          await ApiService.registerDeviceToken(
            newToken,
            platform: platform,
          );
        } catch (_) {}
      });
    } catch (_) {
      // Never block app flows on push setup failures.
    }
  }

  static Future<void> unregister() async {
    if (!_supported) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      await ApiService.unregisterDeviceToken(token: token);
    } catch (_) {}
  }

  static void _handleOpen(RemoteMessage message) {
    final type = message.data['notificationType'] ?? '';
    final tabIndex = _sellerTypes.contains(type) ? 2 : 1;
    final nav = navigatorKey.currentState;
    if (nav == null) return;

    nav.pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => MainShellScreen(initialIndex: tabIndex),
      ),
      (_) => false,
    );
  }
}
