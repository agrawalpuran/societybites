import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'my_listings_cache.dart';

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

  /// In-process cache so clear()/isSignedIn stay responsive if the secure
  /// storage plugin hangs (common in widget tests / some desktop hosts).
  static String? _memoryJwt;
  static String? _memoryRefresh;
  static bool _clearedThisProcess = false;

  static void _secureBestEffort(Future<dynamic> future) {
    future.then((_) {}, onError: (_) {});
  }

  static Future<String?> _secureRead(String key) async {
    if (_clearedThisProcess &&
        (key == _jwtKey ? _memoryJwt : _memoryRefresh) == null) {
      return null;
    }
    try {
      return await _secureStorage
          .read(key: key)
          .timeout(const Duration(seconds: 2));
    } catch (_) {
      return null;
    }
  }

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

  static Future<bool> isSignedIn() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> saveToken(String token) async {
    _memoryJwt = token;
    _clearedThisProcess = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_jwtKey);
    _secureBestEffort(_secureStorage.write(key: _jwtKey, value: token));
  }

  static Future<String?> getToken() async {
    if (_memoryJwt != null && _memoryJwt!.isNotEmpty) return _memoryJwt;
    if (_clearedThisProcess) return null;

    final secureToken = await _secureRead(_jwtKey);
    if (secureToken != null && secureToken.isNotEmpty) {
      _memoryJwt = secureToken;
      return secureToken;
    }

    // Backward-compatible migration for existing Firebase demo sessions.
    final prefs = await SharedPreferences.getInstance();
    final legacyToken = prefs.getString(_jwtKey);
    if (legacyToken != null && legacyToken.isNotEmpty) {
      _memoryJwt = legacyToken;
      _secureBestEffort(_secureStorage.write(key: _jwtKey, value: legacyToken));
      await prefs.remove(_jwtKey);
    }
    return legacyToken;
  }

  static Future<void> saveRefreshToken(String token) async {
    _memoryRefresh = token;
    _clearedThisProcess = false;
    _secureBestEffort(
      _secureStorage.write(key: _refreshTokenKey, value: token),
    );
  }

  static Future<String?> getRefreshToken() async {
    if (_memoryRefresh != null && _memoryRefresh!.isNotEmpty) {
      return _memoryRefresh;
    }
    if (_clearedThisProcess) return null;
    final token = await _secureRead(_refreshTokenKey);
    if (token != null && token.isNotEmpty) {
      _memoryRefresh = token;
    }
    return token;
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
      _memoryRefresh = null;
      _secureBestEffort(_secureStorage.delete(key: _refreshTokenKey));
    }
  }

  static Future<void> clear() async {
    MyListingsCache.clear();
    _memoryJwt = null;
    _memoryRefresh = null;
    _clearedThisProcess = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _secureBestEffort(_secureStorage.delete(key: _jwtKey));
    _secureBestEffort(_secureStorage.delete(key: _refreshTokenKey));
  }
}
