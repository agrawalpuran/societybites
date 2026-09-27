import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:societybites/services/api_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({'auth_provider': '2factor'});
    ApiService.onSessionInvalidated = null;
  });

  tearDown(() {
    ApiService.onSessionInvalidated = null;
  });

  test('startup restore without refresh token does not force LoginScreen',
      () async {
    var loginForced = false;
    ApiService.onSessionInvalidated = () => loginForced = true;

    final restored = await ApiService.restoreTwoFactorSession();

    expect(restored, isFalse);
    expect(loginForced, isFalse);
  });
}
