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

/// iOS FCM tokens are unavailable until APNs has registered.
Future<String?> waitForApnsToken({
  required Future<String?> Function() readToken,
  int attempts = 15,
  Duration delay = const Duration(milliseconds: 400),
}) async {
  for (var i = 0; i < attempts; i++) {
    final token = await readToken();
    if (token != null && token.isNotEmpty) return token;
    await Future.delayed(delay);
  }
  return null;
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
  static int _tokenRetries = 0;

  static bool get _supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  static Future<void> init() async {
    try {
      if (!_supported || _initialized) return;
      _initialized = true;

      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await FirebaseMessaging.instance.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      FirebaseMessaging.onMessage.listen((message) {
        if (kDebugMode) {
          debugPrint(
            '[push] onMessage type=${message.data['notificationType'] ?? 'none'}',
          );
        }
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

      final platform = Platform.isIOS ? 'ios' : 'android';
      if (!_tokenRefreshBound) {
        _tokenRefreshBound = true;
        messaging.onTokenRefresh.listen((newToken) async {
          await _saveDeviceToken(newToken, platform);
        });
      }

      final token = await _fcmToken(messaging);
      if (kDebugMode) {
        debugPrint(
          '[push] fcmToken ${token == null || token.isEmpty ? 'missing' : 'obtained'}',
        );
      }
      if (token == null || token.isEmpty) {
        _scheduleTokenRetry();
        return;
      }

      _tokenRetries = 0;
      await _saveDeviceToken(token, platform);
    } catch (err) {
      if (kDebugMode) {
        debugPrint('[push] registerIfPossible failed: $err');
      }
    }
  }

  static void _scheduleTokenRetry() {
    if (_tokenRetries >= 4) return;
    _tokenRetries += 1;
    final wait = Duration(seconds: 4 * _tokenRetries);
    Future.delayed(wait, () {
      if (_supported) registerIfPossible();
    });
  }

  static Future<void> _saveDeviceToken(String token, String platform) async {
    if (token.isEmpty) return;
    try {
      await ApiService.registerDeviceToken(token, platform: platform);
      if (kDebugMode) {
        debugPrint('[push] device token registered');
      }
    } catch (err) {
      if (kDebugMode) {
        debugPrint('[push] device token register failed: $err');
      }
    }
  }

  static Future<String?> _fcmToken(FirebaseMessaging messaging) async {
    if (Platform.isIOS) {
      final apns = await waitForApnsToken(readToken: messaging.getAPNSToken);
      if (apns == null || apns.isEmpty) {
        if (kDebugMode) {
          debugPrint('[push] APNS token not ready');
        }
        return null;
      }
    }
    return messaging.getToken();
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
    onForegroundOrderUpdate?.call();
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
