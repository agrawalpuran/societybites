import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:societybites/firebase_options.dart';
import 'package:societybites/services/push_notification_service.dart';

void main() {
  test('iOS Firebase options match the shipped GoogleService-Info app', () {
    expect(DefaultFirebaseOptions.ios.iosBundleId, 'com.societybites.app');
    expect(
      DefaultFirebaseOptions.ios.appId,
      '1:959244904791:ios:18180ea77ee7072b91f612',
    );
  });

  test('waits until an APNs token is available', () async {
    var calls = 0;
    final token = await waitForApnsToken(
      readToken: () async {
        calls += 1;
        return calls >= 3 ? 'apns-token' : null;
      },
      delay: Duration.zero,
    );
    expect(token, 'apns-token');
    expect(calls, 3);
  });

  test('iOS shows a banner while the app is in the foreground', () {
    final source = File('ios/Runner/AppDelegate.swift').readAsStringSync();
    expect(source.contains('willPresent notification'), isTrue);
    expect(source.contains('.banner'), isTrue);
    expect(source.contains('.sound'), isTrue);
  });

  test('gives up when APNs never arrives', () async {
    final token = await waitForApnsToken(
      readToken: () async => null,
      attempts: 2,
      delay: Duration.zero,
    );
    expect(token, isNull);
  });
}
