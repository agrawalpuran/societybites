import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  static const _secureStorage = FlutterSecureStorage();
  static const _userIdKey = 'user_id';
  static const _phoneKey = 'phone';
  static const _userNameKey = 'user_name';
  static const _societyIdKey = 'society_id';
  static const _societyNameKey = 'society_name';
  static const _flatIdKey = 'flat_id';
  static const _flatNumberKey = 'flat_number';
  static const _roleKey = 'user_role';
  static const _jwtKey = 'auth_token';
  static const _refreshTokenKey = 'refresh_token';
  static const _authProviderKey = 'auth_provider';

  static const defaultSocietyId = 'prestige-notting-hill';
  static const defaultSocietyName = 'Prestige Notting Hill';

  static Future<void> saveUser({
    required String userId,
    required String phone,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userIdKey, userId);
    await prefs.setString(_phoneKey, phone);
  }

  static Future<void> saveSociety({
    required String societyId,
    required String societyName,
    required String flatId,
    String? flatNumber,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_societyIdKey, societyId);
    await prefs.setString(_societyNameKey, societyName);
    await prefs.setString(_flatIdKey, flatId);
    if (flatNumber != null) {
      await prefs.setString(_flatNumberKey, flatNumber);
    }
  }

  static Future<void> saveUserName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userNameKey, name);
  }

  static Future<void> cacheProfileFromApi(Map<String, dynamic> profile) async {
    final prefs = await SharedPreferences.getInstance();
    final name = profile['name'] as String?;
    final society = profile['society'] as Map<String, dynamic>?;
    final flat = profile['flat'] as Map<String, dynamic>?;

    if (name != null && name.isNotEmpty) {
      await prefs.setString(_userNameKey, name);
    }
    if (society?['name'] != null) {
      await prefs.setString(_societyNameKey, society!['name'] as String);
    }
    if (profile['societyId'] != null) {
      await prefs.setString(_societyIdKey, profile['societyId'] as String);
    }
    if (profile['flatId'] != null) {
      await prefs.setString(_flatIdKey, profile['flatId'] as String);
    }
    if (flat?['flatNumber'] != null) {
      await prefs.setString(_flatNumberKey, flat!['flatNumber'] as String);
    }
    if (profile['role'] != null) {
      await prefs.setString(_roleKey, profile['role'] as String);
    }
  }

  static Future<String?> getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userIdKey);
  }

  static Future<String?> getPhone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_phoneKey);
  }

  static Future<String?> getSocietyId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_societyIdKey);
  }

  static Future<String?> getSocietyName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_societyNameKey);
  }

  static Future<String?> getFlatId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_flatIdKey);
  }

  static Future<String?> getUserName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_userNameKey);
  }

  static Future<String?> getFlatNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_flatNumberKey);
  }

  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_roleKey);
  }

  static Future<bool> isOnboarded() async {
    final userId = await getUserId();
    final societyId = await getSocietyId();
    final flatId = await getFlatId();
    return userId != null &&
        societyId != null &&
        flatId != null &&
        flatId.isNotEmpty;
  }

  static Future<void> saveToken(String token) async {
    await _secureStorage.write(key: _jwtKey, value: token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_jwtKey);
  }

  static Future<String?> getToken() async {
    final secureToken = await _secureStorage.read(key: _jwtKey);
    if (secureToken != null && secureToken.isNotEmpty) return secureToken;

    // Backward-compatible migration for existing Firebase demo sessions.
    final prefs = await SharedPreferences.getInstance();
    final legacyToken = prefs.getString(_jwtKey);
    if (legacyToken != null && legacyToken.isNotEmpty) {
      await _secureStorage.write(key: _jwtKey, value: legacyToken);
      await prefs.remove(_jwtKey);
    }
    return legacyToken;
  }

  static Future<void> saveRefreshToken(String token) async {
    await _secureStorage.write(key: _refreshTokenKey, value: token);
  }

  static Future<String?> getRefreshToken() async {
    return _secureStorage.read(key: _refreshTokenKey);
  }

  static Future<void> saveAuthProvider(String provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_authProviderKey, provider);
  }

  static Future<String> getAuthProvider() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_authProviderKey) ?? 'firebase';
  }

  static Future<void> saveAuthSession({
    required String accessToken,
    required String provider,
    String? refreshToken,
  }) async {
    await saveToken(accessToken);
    await saveAuthProvider(provider);
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await saveRefreshToken(refreshToken);
    } else {
      await _secureStorage.delete(key: _refreshTokenKey);
    }
  }

  static Future<void> clear() async {
    await _secureStorage.delete(key: _jwtKey);
    await _secureStorage.delete(key: _refreshTokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}
