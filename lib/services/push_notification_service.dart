import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../firebase_options.dart';
import 'api_service.dart';
import '../screens/main_shell_screen.dart';

/// Top-level background handler (must be a top-level or static function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
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

  static const _androidChannel = MethodChannel('societybites/notifications');

  static bool _initialized = false;
  static bool _tokenRefreshBound = false;

  static bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<void> init() async {
    if (!_supported || _initialized) return;
    _initialized = true;

    try {
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      FirebaseMessaging.onMessage.listen((message) {
        onForegroundOrderUpdate?.call();
        _showAndroidForegroundNotification(message);
      });

      FirebaseMessaging.onMessageOpenedApp.listen(_handleOpen);

      try {
        final initial = await FirebaseMessaging.instance.getInitialMessage();
        if (initial != null) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _handleOpen(initial),
          );
        }
      } catch (err) {
        debugPrint('[push] getInitialMessage failed: $err');
      }
    } catch (err) {
      debugPrint('[push] init failed: $err');
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

      if (kDebugMode) {
        debugPrint(
          '[push] platform=${Platform.isIOS ? 'ios' : 'android'} '
          'authorizationStatus=${settings.authorizationStatus}',
        );
      }

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      final token = await messaging.getToken();
      if (kDebugMode) {
        debugPrint(
          '[push] fcmToken ${token == null || token.isEmpty ? 'missing' : 'obtained'}',
        );
      }
      if (token == null || token.isEmpty) return;

      final platform = Platform.isIOS ? 'ios' : 'android';
      await ApiService.registerDeviceToken(token, platform: platform);
      if (kDebugMode) {
        debugPrint('[push] device token registered');
      }

      if (!_tokenRefreshBound) {
        _tokenRefreshBound = true;
        messaging.onTokenRefresh.listen((newToken) async {
          try {
            await ApiService.registerDeviceToken(
              newToken,
              platform: platform,
            );
            if (kDebugMode) {
              debugPrint('[push] refreshed device token registered');
            }
          } catch (err) {
            if (kDebugMode) {
              debugPrint('[push] token refresh register failed');
            }
          }
        });
      }
    } catch (err) {
      if (kDebugMode) {
        debugPrint('[push] registerIfPossible failed: $err');
      }
    }
  }

  static Future<void> unregister() async {
    if (!_supported) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      await ApiService.unregisterDeviceToken(token: token);
    } catch (_) {}
  }

  static Future<void> _showAndroidForegroundNotification(
    RemoteMessage message,
  ) async {
    if (kIsWeb || !Platform.isAndroid) return;
    final title = message.notification?.title ?? 'SocietyBites';
    final body = message.notification?.body ?? '';
    if (body.isEmpty && message.notification?.title == null) return;
    try {
      await _androidChannel.invokeMethod('show', {
        'title': title,
        'body': body,
      });
    } catch (err) {
      if (kDebugMode) {
        debugPrint('[push] foreground local notification failed');
      }
    }
  }

  static void _handleOpen(RemoteMessage message) {
    final type = message.data['notificationType'] ?? '';
    final recipientRole = message.data['recipientRole'] ?? '';
    final tabIndex = type == 'order_message'
        ? (recipientRole == 'seller' ? 2 : 1)
        : (_sellerTypes.contains(type) ? 2 : 1);
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
