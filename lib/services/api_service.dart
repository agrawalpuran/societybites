import 'dart:convert';

import 'package:flutter/foundation.dart' show VoidCallback;
import 'package:http/http.dart' as http_client;

import 'auth_config.dart';
import 'session_service.dart';

final http = _RefreshAwareHttp();

Map<String, dynamic> buildOrderReadyTimePayload({
  DateTime? expectedReadyAt,
  num? readyInMinutes,
}) {
  if (expectedReadyAt != null && readyInMinutes != null) {
    throw ArgumentError(
      'Provide either expectedReadyAt or readyInMinutes, not both',
    );
  }
  return {
    if (readyInMinutes != null)
      'readyInMinutes': readyInMinutes
    else
      'expectedReadyAt': expectedReadyAt?.toUtc().toIso8601String(),
  };
}

class _RefreshAwareHttp {
  Future<http_client.Response> get(Uri url, {Map<String, String>? headers}) {
    return _send('GET', url, headers: headers);
  }

  Future<http_client.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return _send('POST', url, headers: headers, body: body);
  }

  Future<http_client.Response> patch(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return _send('PATCH', url, headers: headers, body: body);
  }

  Future<http_client.Response> delete(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) {
    return _send('DELETE', url, headers: headers, body: body);
  }

  Future<http_client.Response> _send(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    bool allowRefresh = true,
  }) async {
    final response = await _sendRaw(method, url, headers: headers, body: body);
    final wasAuthenticated = headers?.containsKey('Authorization') ?? false;

    if (allowRefresh &&
        wasAuthenticated &&
        ApiService._isUnauthorizedResponse(response)) {
      final requestAuthorization = headers?['Authorization'];
      final currentToken = await SessionService.getToken();
      final currentAuthorization = currentToken == null
          ? null
          : 'Bearer $currentToken';

      // Another request may already have completed the single-flight refresh.
      // In that case, retry once with its new token instead of rotating again.
      if (currentAuthorization != null &&
          currentAuthorization != requestAuthorization) {
        final retryHeaders = Map<String, String>.from(headers ?? const {});
        retryHeaders['Authorization'] = currentAuthorization;
        return _sendRaw(method, url, headers: retryHeaders, body: body);
      }

      if (!await ApiService._refreshAccessToken()) return response;

      final retryHeaders = Map<String, String>.from(headers ?? const {});
      final token = await SessionService.getToken();
      if (token != null) retryHeaders['Authorization'] = 'Bearer $token';
      return _sendRaw(method, url, headers: retryHeaders, body: body);
    }

    return response;
  }

  Future<http_client.Response> _sendRaw(
    String method,
    Uri url, {
    Map<String, String>? headers,
    Object? body,
  }) {
    switch (method) {
      case 'POST':
        return http_client.post(url, headers: headers, body: body);
      case 'PATCH':
        return http_client.patch(url, headers: headers, body: body);
      case 'DELETE':
        return http_client.delete(url, headers: headers, body: body);
      default:
        return http_client.get(url, headers: headers);
    }
  }
}

class TokenExpiredException implements Exception {
  final String message;
  TokenExpiredException(this.message);
  @override
  String toString() => message;
}

class ApiService {
  static Future<bool>? _refreshInFlight;
  static VoidCallback? onSessionInvalidated;

  static String get baseUrl {
    const configured = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://societybites.onrender.com',
    );
    final normalized = configured.trim();
    if (normalized.isEmpty) return 'https://societybites.onrender.com';
    return normalized.endsWith('/')
        ? normalized.substring(0, normalized.length - 1)
        : normalized;
  }

  static String absoluteUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) {
      return path;
    }
    if (path.startsWith('/')) {
      return '$baseUrl$path';
    }
    return '$baseUrl/$path';
  }

  /// Resolves a listing image path and busts browser cache when the listing changes.
  static String imageUrl(String path, {String? cacheKey}) {
    final url = absoluteUrl(path);
    if (cacheKey == null || cacheKey.isEmpty) return url;
    final separator = url.contains('?') ? '&' : '?';
    return '$url${separator}v=${Uri.encodeComponent(cacheKey)}';
  }

  static Future<Map<String, String>> _authHeaders() async {
    final token = await SessionService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static dynamic _decodeResponse(http_client.Response response) {
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  static Never _throwFromResponse(http_client.Response response) {
    final body = _decodeResponse(response);
    final message = body is Map && body['error'] != null
        ? body['error'].toString()
        : response.body;

    if (response.statusCode == 401 &&
        body is Map &&
        body['code'] == 'TOKEN_EXPIRED') {
      throw TokenExpiredException(message);
    }

    throw Exception(message);
  }

  static bool _isUnauthorizedResponse(http_client.Response response) =>
      response.statusCode == 401;

  static Future<bool> _refreshAccessToken() {
    final active = _refreshInFlight;
    if (active != null) return active;

    final future = _performRefresh();
    _refreshInFlight = future;
    return future.whenComplete(() => _refreshInFlight = null);
  }

  static Future<bool> _performRefresh() async {
    if (!AuthConfig.usesTwoFactor ||
        await SessionService.getAuthProvider() != '2factor') {
      return false;
    }

    final refreshToken = await SessionService.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await _invalidateSession();
      return false;
    }

    try {
      final response = await http_client.post(
        Uri.parse('$baseUrl/auth/refresh'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );
      if (response.statusCode != 200) {
        await _invalidateSession();
        return false;
      }

      final data = Map<String, dynamic>.from(_decodeResponse(response) as Map);
      final access = data['token'] as String?;
      final refresh = data['refreshToken'] as String?;
      if (access == null || refresh == null) {
        await _invalidateSession();
        return false;
      }

      await SessionService.saveAuthSession(
        accessToken: access,
        refreshToken: refresh,
        provider: '2factor',
      );
      final user = data['user'];
      if (user is Map) {
        final profile = Map<String, dynamic>.from(user);
        await SessionService.cacheProfileFromApi(profile);
        final userId = profile['id'] as String?;
        final phone = profile['phone'] as String?;
        if (userId != null && phone != null) {
          await SessionService.saveUser(userId: userId, phone: phone);
        }
      }
      return true;
    } catch (_) {
      await _invalidateSession();
      return false;
    }
  }

  static Future<void> _invalidateSession() async {
    await SessionService.clear();
    onSessionInvalidated?.call();
  }

  static Future<Map<String, dynamic>> firebaseLogin(
    String firebaseToken,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/firebase-login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'firebaseToken': firebaseToken}),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<void> sendOtp(String phone) async {
    final response = await http_client.post(
      Uri.parse('$baseUrl/auth/send-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone}),
    );
    if (response.statusCode == 200) return;
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> verifyOtp({
    required String phone,
    required String otp,
  }) async {
    final response = await http_client.post(
      Uri.parse('$baseUrl/auth/verify-otp'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone, 'otp': otp}),
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<bool> restoreTwoFactorSession() async {
    if (!AuthConfig.usesTwoFactor) return false;
    if (await SessionService.getAuthProvider() != '2factor') return false;
    final refreshToken = await SessionService.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await _invalidateSession();
      return false;
    }

    // Startup performs exactly one rotation. Successful refresh responses
    // already include and cache the authoritative backend user.
    return _refreshAccessToken();
  }

  static Future<void> logoutTwoFactor() async {
    final refreshToken = await SessionService.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return;
    try {
      await http_client.post(
        Uri.parse('$baseUrl/auth/logout'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refreshToken': refreshToken}),
      );
    } catch (_) {
      // Local session clearing must still succeed if logout is offline.
    }
  }

  static Future<Map<String, dynamic>> getMe() async {
    final response = await http.get(
      Uri.parse('$baseUrl/auth/me'),
      headers: await _authHeaders(),
    );

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> updateMyProfile({
    String? name,
    String? role,
    String? societyId,
    String? flatId,
    String? upiId,
    String? upiDisplayName,
    bool? paymentEnabled,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/auth/me/profile'),
      headers: await _authHeaders(),
      body: jsonEncode({
        if (name != null) 'name': name,
        if (role != null) 'role': role,
        if (societyId != null) 'societyId': societyId,
        if (flatId != null) 'flatId': flatId,
        if (upiId != null) 'upiId': upiId,
        if (upiDisplayName != null) 'upiDisplayName': upiDisplayName,
        if (paymentEnabled != null) 'paymentEnabled': paymentEnabled,
      }),
    );

    if (response.statusCode == 200) {
      final data = Map<String, dynamic>.from(_decodeResponse(response) as Map);
      if (data['token'] != null &&
          await SessionService.getAuthProvider() == 'firebase') {
        await SessionService.saveToken(data['token'] as String);
      }
      return Map<String, dynamic>.from(data['user'] as Map);
    }
    _throwFromResponse(response);
  }

  static Future<List<Map<String, dynamic>>> getSocieties() async {
    final response = await http.get(
      Uri.parse('$baseUrl/societies'),
      headers: await _authHeaders(),
    );
    if (response.statusCode == 200) {
      final data = _decodeResponse(response);
      if (data is List) {
        return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> joinSociety({
    required String societyId,
    required String flatNumber,
    required String block,
    required String firstName,
    String? lastName,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/societies/join'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'societyId': societyId,
        'flatNumber': flatNumber,
        'block': block,
        'firstName': firstName,
        if (lastName != null && lastName.trim().isNotEmpty)
          'lastName': lastName.trim(),
      }),
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> validateFlat({
    required String societyId,
    required String flatNumber,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/societies/$societyId/validate-flat'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'flatNumber': flatNumber}),
    );

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<List<Map<String, dynamic>>> getListings({
    required String societyId,
    String? sellerId,
    String? search,
    String? status,
  }) async {
    final query = <String, String>{'societyId': societyId};
    if (sellerId != null) query['sellerId'] = sellerId;
    if (search != null && search.trim().isNotEmpty) {
      query['search'] = search.trim();
    }
    if (status != null && status.isNotEmpty) {
      query['status'] = status;
    }

    final uri = Uri.parse('$baseUrl/listings').replace(queryParameters: query);
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final data = _decodeResponse(response) as List;
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> createListing({
    required String societyId,
    required String name,
    required double price,
    int quantity = 1,
    String? description,
    DateTime? availableAt,
    String? pickupLocation,
    String? imageUrl,
    String? weightUnit,
    String? weightValue,
    List<String>? tags,
    String? category,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/listings'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'societyId': societyId,
        'name': name,
        'price': price,
        'quantity': quantity,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (availableAt != null) 'availableAt': availableAt.toIso8601String(),
        if (pickupLocation != null) 'pickupLocation': pickupLocation,
        if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
        if (weightUnit != null && weightUnit.isNotEmpty)
          'weightUnit': weightUnit,
        if (weightValue != null && weightValue.isNotEmpty)
          'weightValue': weightValue,
        if (tags != null && tags.isNotEmpty) 'tags': tags,
        if (category != null && category.isNotEmpty) 'category': category,
      }),
    );

    if (response.statusCode == 201) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<String> uploadListingImage({
    required List<int> bytes,
    String mimeType = 'image/jpeg',
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/media/upload'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'imageBase64': base64Encode(bytes),
        'mimeType': mimeType,
      }),
    );

    if (response.statusCode == 201) {
      final data = Map<String, dynamic>.from(_decodeResponse(response) as Map);
      return data['imageUrl'] as String;
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> createOrder({
    required String societyId,
    required List<Map<String, dynamic>> items,
    String paymentMethod = 'upi',
    String type = 'regular',
    String? campaignId,
    String? fulfilmentMethod,
    String? fulfilmentNotes,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/orders'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'societyId': societyId,
        'paymentMethod': paymentMethod,
        'type': type,
        if (campaignId != null) 'campaignId': campaignId,
        if (fulfilmentMethod != null) 'fulfilmentMethod': fulfilmentMethod,
        if (fulfilmentNotes != null && fulfilmentNotes.trim().isNotEmpty)
          'fulfilmentNotes': fulfilmentNotes.trim(),
        'items': items,
      }),
    );

    if (response.statusCode == 201) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> updateListing({
    required String listingId,
    String? name,
    String? description,
    double? price,
    int? quantity,
    DateTime? availableAt,
    String? pickupLocation,
    String? imageUrl,
    String? status,
    String? weightUnit,
    String? weightValue,
    List<String>? tags,
    String? category,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/listings/$listingId'),
      headers: await _authHeaders(),
      body: jsonEncode({
        if (name != null) 'name': name,
        if (description != null) 'description': description,
        if (price != null) 'price': price,
        if (quantity != null) 'quantity': quantity,
        if (availableAt != null) 'availableAt': availableAt.toIso8601String(),
        if (pickupLocation != null) 'pickupLocation': pickupLocation,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (status != null) 'status': status,
        if (weightUnit != null) 'weightUnit': weightUnit,
        if (weightValue != null) 'weightValue': weightValue,
        if (tags != null) 'tags': tags,
        if (category != null) 'category': category,
      }),
    );

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<void> deleteListing(String listingId) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/listings/$listingId'),
      headers: await _authHeaders(),
    );

    if (response.statusCode == 200) {
      return;
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> pauseListing(String listingId) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/listings/$listingId/pause'),
      headers: await _authHeaders(),
    );

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> resumeListing(String listingId) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/listings/$listingId/resume'),
      headers: await _authHeaders(),
    );

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> renewListing({
    required String listingId,
    required DateTime availableAt,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/listings/$listingId/renew'),
      headers: await _authHeaders(),
      body: jsonEncode({'availableAt': availableAt.toIso8601String()}),
    );

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<List<Map<String, dynamic>>> getOrders({
    String role = 'buyer',
    String? status,
  }) async {
    final query = <String, String>{'role': role};
    if (status != null) query['status'] = status;

    final uri = Uri.parse('$baseUrl/orders').replace(queryParameters: query);
    final response = await http.get(uri, headers: await _authHeaders());

    if (response.statusCode == 200) {
      final data = _decodeResponse(response) as List;
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> getOrderById(String orderId) async {
    final response = await http.get(
      Uri.parse('$baseUrl/orders/$orderId'),
      headers: await _authHeaders(),
    );

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> updateOrderStatus({
    required String orderId,
    required String status,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/orders/$orderId/status'),
      headers: await _authHeaders(),
      body: jsonEncode({'status': status}),
    );

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  /// Set or clear optional Ready-by estimate. Pass null to clear.
  static Future<Map<String, dynamic>> setOrderReadyTime({
    required String orderId,
    DateTime? expectedReadyAt,
    num? readyInMinutes,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/orders/$orderId/ready-time'),
      headers: await _authHeaders(),
      body: jsonEncode(
        buildOrderReadyTimePayload(
          expectedReadyAt: expectedReadyAt,
          readyInMinutes: readyInMinutes,
        ),
      ),
    );

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> rejectOrder({
    required String orderId,
    required String reason,
    String? otherText,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/orders/$orderId/reject'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'reason': reason,
        if (otherText != null && otherText.trim().isNotEmpty)
          'otherText': otherText.trim(),
      }),
    );

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> getSellerStats() async {
    final response = await http.get(
      Uri.parse('$baseUrl/orders/seller/stats'),
      headers: await _authHeaders(),
    );

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<List<Map<String, dynamic>>> getPreOrderCampaigns({
    required String societyId,
    String? sellerId,
    String? status,
  }) async {
    final query = <String, String>{'societyId': societyId};
    if (sellerId != null) query['sellerId'] = sellerId;
    if (status != null) query['status'] = status;
    final uri = Uri.parse(
      '$baseUrl/preorder-campaigns',
    ).replace(queryParameters: query);
    final response = await http.get(uri, headers: await _authHeaders());
    if (response.statusCode == 200) {
      final data = _decodeResponse(response) as List;
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> getPreOrderCampaign(String id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/preorder-campaigns/$id'),
      headers: await _authHeaders(),
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> createPreOrderCampaign({
    required String title,
    String? description,
    required DateTime orderOpenAt,
    required DateTime orderCutoffAt,
    required DateTime fulfilmentAt,
    required List<String> offeredFulfilmentMethods,
    double defaultDeliveryCharge = 0,
    String status = 'draft',
    String? coverImageUrl,
    String? fulfilmentNotes,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/preorder-campaigns'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'title': title,
        if (description != null && description.trim().isNotEmpty)
          'description': description.trim(),
        'orderOpenAt': orderOpenAt.toUtc().toIso8601String(),
        'orderCutoffAt': orderCutoffAt.toUtc().toIso8601String(),
        'fulfilmentAt': fulfilmentAt.toUtc().toIso8601String(),
        'offeredFulfilmentMethods': offeredFulfilmentMethods,
        'defaultDeliveryCharge': defaultDeliveryCharge,
        'status': status,
        if (coverImageUrl != null && coverImageUrl.trim().isNotEmpty)
          'coverImageUrl': coverImageUrl.trim(),
        if (fulfilmentNotes != null && fulfilmentNotes.trim().isNotEmpty)
          'fulfilmentNotes': fulfilmentNotes.trim(),
      }),
    );
    if (response.statusCode == 201) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> updatePreOrderCampaign({
    required String id,
    String? status,
    String? title,
    String? description,
    String? coverImageUrl,
    bool clearCoverImage = false,
    String? fulfilmentNotes,
    DateTime? orderOpenAt,
    DateTime? orderCutoffAt,
    DateTime? fulfilmentAt,
    List<String>? offeredFulfilmentMethods,
    double? defaultDeliveryCharge,
  }) async {
    final payload = <String, dynamic>{};
    if (status != null) payload['status'] = status;
    if (title != null) payload['title'] = title.trim();
    if (description != null) payload['description'] = description.trim();
    if (coverImageUrl != null) {
      payload['coverImageUrl'] = coverImageUrl.trim();
    } else if (clearCoverImage) {
      payload['coverImageUrl'] = null;
    }
    if (fulfilmentNotes != null) {
      payload['fulfilmentNotes'] = fulfilmentNotes.trim();
    }
    if (orderOpenAt != null) {
      payload['orderOpenAt'] = orderOpenAt.toUtc().toIso8601String();
    }
    if (orderCutoffAt != null) {
      payload['orderCutoffAt'] = orderCutoffAt.toUtc().toIso8601String();
    }
    if (fulfilmentAt != null) {
      payload['fulfilmentAt'] = fulfilmentAt.toUtc().toIso8601String();
    }
    if (offeredFulfilmentMethods != null) {
      payload['offeredFulfilmentMethods'] = offeredFulfilmentMethods;
    }
    if (defaultDeliveryCharge != null) {
      payload['defaultDeliveryCharge'] = defaultDeliveryCharge;
    }
    final response = await http.patch(
      Uri.parse('$baseUrl/preorder-campaigns/$id'),
      headers: await _authHeaders(),
      body: jsonEncode(payload),
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> addPreOrderProduct({
    required String campaignId,
    required String name,
    required double price,
    required String inventoryMode,
    int? maxQuantity,
    String? description,
    String? imageUrl,
    String? weightUnit,
    String? weightValue,
    List<String>? tags,
    String? category,
    String? pickupLocation,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/preorder-campaigns/$campaignId/products'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'name': name,
        'price': price,
        'inventoryMode': inventoryMode,
        if (inventoryMode == 'limited') 'quantity': maxQuantity,
        if (description != null && description.isNotEmpty)
          'description': description,
        if (imageUrl != null && imageUrl.isNotEmpty) 'imageUrl': imageUrl,
        if (weightUnit != null && weightUnit.isNotEmpty)
          'weightUnit': weightUnit,
        if (weightValue != null && weightValue.isNotEmpty)
          'weightValue': weightValue,
        if (tags != null && tags.isNotEmpty) 'tags': tags,
        if (category != null && category.isNotEmpty) 'category': category,
        if (pickupLocation != null && pickupLocation.isNotEmpty)
          'pickupLocation': pickupLocation,
      }),
    );
    if (response.statusCode == 201) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> updatePreOrderProduct({
    required String campaignId,
    required String productId,
    required String name,
    required double price,
    required String inventoryMode,
    int? maxQuantity,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/preorder-campaigns/$campaignId/products/$productId'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'name': name.trim(),
        'price': price,
        'inventoryMode': inventoryMode,
        'quantity': inventoryMode == 'limited' ? maxQuantity : 0,
      }),
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<void> deletePreOrderProduct({
    required String campaignId,
    required String productId,
  }) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/preorder-campaigns/$campaignId/products/$productId'),
      headers: await _authHeaders(),
    );
    if (response.statusCode == 204) return;
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> getPreOrderSummary(String id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/preorder-campaigns/$id/summary'),
      headers: await _authHeaders(),
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<List<Map<String, dynamic>>> getPreOrderOrders(String id) async {
    final response = await http.get(
      Uri.parse('$baseUrl/preorder-campaigns/$id/orders'),
      headers: await _authHeaders(),
    );
    if (response.statusCode == 200) {
      final data = _decodeResponse(response) as List;
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    _throwFromResponse(response);
  }

  static Future<List<Map<String, dynamic>>> getListingReviews(
    String listingId,
  ) async {
    final response = await http.get(
      Uri.parse('$baseUrl/reviews/listing/$listingId'),
    );

    if (response.statusCode == 200) {
      final data = _decodeResponse(response) as List;
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    _throwFromResponse(response);
  }

  static Future<List<Map<String, dynamic>>> getSellerReviews() async {
    final response = await http.get(
      Uri.parse('$baseUrl/reviews/seller/me'),
      headers: await _authHeaders(),
    );

    if (response.statusCode == 200) {
      final data = _decodeResponse(response) as List;
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> submitReview({
    required String orderId,
    required String listingId,
    required int rating,
    String? comment,
    List<String> tags = const [],
    bool wouldOrderAgain = true,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/reviews'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'orderId': orderId,
        'listingId': listingId,
        'rating': rating,
        if (comment != null && comment.isNotEmpty) 'comment': comment,
        'tags': tags,
        'wouldOrderAgain': wouldOrderAgain,
      }),
    );

    if (response.statusCode == 201) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> markOrderPaid({
    required String orderId,
    String? upiTransactionRef,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/payments/$orderId/mark-paid'),
      headers: await _authHeaders(),
      body: jsonEncode({
        if (upiTransactionRef != null) 'upiTransactionRef': upiTransactionRef,
      }),
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> confirmPayment({
    required String orderId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/payments/$orderId/confirm'),
      headers: await _authHeaders(),
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  /// Seller confirms COD/cash received after pickup.
  static Future<Map<String, dynamic>> confirmCashPayment({
    required String orderId,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/payments/$orderId/confirm-cash'),
      headers: await _authHeaders(),
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> getPaymentStatus({
    required String orderId,
  }) async {
    final response = await http.get(
      Uri.parse('$baseUrl/payments/$orderId'),
      headers: await _authHeaders(),
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  // ─── Admin APIs ───────────────────────────────────────────────────────

  static Future<double> getPlatformFee() async {
    final response = await http.get(Uri.parse('$baseUrl/settings'));
    if (response.statusCode == 200) {
      final data = Map<String, dynamic>.from(_decodeResponse(response) as Map);
      return (data['platformFee'] as num?)?.toDouble() ?? 0;
    }
    _throwFromResponse(response);
  }

  static Future<double> getAdminPlatformFee() async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/settings'),
      headers: await _authHeaders(),
    );
    if (response.statusCode == 200) {
      final data = Map<String, dynamic>.from(_decodeResponse(response) as Map);
      return (data['platformFee'] as num?)?.toDouble() ?? 0;
    }
    _throwFromResponse(response);
  }

  static Future<double> updateAdminPlatformFee(double platformFee) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/admin/settings'),
      headers: await _authHeaders(),
      body: jsonEncode({'platformFee': platformFee}),
    );
    if (response.statusCode == 200) {
      final data = Map<String, dynamic>.from(_decodeResponse(response) as Map);
      return (data['platformFee'] as num?)?.toDouble() ?? platformFee;
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> getAdminDashboard() async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/dashboard'),
      headers: await _authHeaders(),
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<List<Map<String, dynamic>>> getAdminUsers({
    String? search,
    String? role,
    int page = 1,
  }) async {
    final query = <String, String>{'page': '$page'};
    if (search != null && search.isNotEmpty) query['search'] = search;
    if (role != null && role.isNotEmpty) query['role'] = role;
    final uri = Uri.parse(
      '$baseUrl/admin/users',
    ).replace(queryParameters: query);
    final response = await http.get(uri, headers: await _authHeaders());
    if (response.statusCode == 200) {
      final data = _decodeResponse(response);
      if (data is Map && data['users'] != null) {
        return (data['users'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      return (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> updateAdminUser(
    String userId, {
    String? role,
    bool? suspended,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/admin/users/$userId'),
      headers: await _authHeaders(),
      body: jsonEncode({
        if (role != null) 'role': role,
        if (suspended != null) 'suspended': suspended,
      }),
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<List<Map<String, dynamic>>> getAdminSocieties() async {
    final response = await http.get(
      Uri.parse('$baseUrl/admin/societies'),
      headers: await _authHeaders(),
    );
    if (response.statusCode == 200) {
      final data = _decodeResponse(response) as List;
      return data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> createAdminSociety({
    required String name,
    required String city,
    required String inviteCode,
    String? address,
    String? state,
    String? pincode,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/societies'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'name': name,
        'city': city,
        'inviteCode': inviteCode,
        if (address != null) 'address': address,
        if (state != null) 'state': state,
        if (pincode != null) 'pincode': pincode,
      }),
    );
    if (response.statusCode == 201 || response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> updateAdminSociety(
    String societyId, {
    String? name,
    String? city,
    String? address,
    String? state,
    String? pincode,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/admin/societies/$societyId'),
      headers: await _authHeaders(),
      body: jsonEncode({
        if (name != null) 'name': name,
        if (city != null) 'city': city,
        if (address != null) 'address': address,
        if (state != null) 'state': state,
        if (pincode != null) 'pincode': pincode,
      }),
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> regenerateInviteCode(
    String societyId,
  ) async {
    final response = await http.post(
      Uri.parse('$baseUrl/admin/societies/$societyId/regenerate-code'),
      headers: await _authHeaders(),
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<List<Map<String, dynamic>>> getAdminListings({
    String? search,
    int page = 1,
  }) async {
    final query = <String, String>{'page': '$page'};
    if (search != null && search.isNotEmpty) query['search'] = search;
    final uri = Uri.parse(
      '$baseUrl/admin/listings',
    ).replace(queryParameters: query);
    final response = await http.get(uri, headers: await _authHeaders());
    if (response.statusCode == 200) {
      final data = _decodeResponse(response);
      if (data is Map && data['listings'] != null) {
        return (data['listings'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      return (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> updateAdminListing(
    String listingId, {
    String? status,
    bool? featured,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/admin/listings/$listingId'),
      headers: await _authHeaders(),
      body: jsonEncode({
        if (status != null) 'status': status,
        if (featured != null) 'featured': featured,
      }),
    );
    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<List<Map<String, dynamic>>> getAdminOrders({
    String? status,
    int page = 1,
  }) async {
    final query = <String, String>{'page': '$page'};
    if (status != null && status.isNotEmpty) query['status'] = status;
    final uri = Uri.parse(
      '$baseUrl/admin/orders',
    ).replace(queryParameters: query);
    final response = await http.get(uri, headers: await _authHeaders());
    if (response.statusCode == 200) {
      final data = _decodeResponse(response);
      if (data is Map && data['orders'] != null) {
        return (data['orders'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      return (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    _throwFromResponse(response);
  }

  static Future<List<Map<String, dynamic>>> getAdminReviews({
    int page = 1,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/admin/reviews',
    ).replace(queryParameters: {'page': '$page'});
    final response = await http.get(uri, headers: await _authHeaders());
    if (response.statusCode == 200) {
      final data = _decodeResponse(response);
      if (data is Map && data['reviews'] != null) {
        return (data['reviews'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      return (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    _throwFromResponse(response);
  }

  static Future<List<Map<String, dynamic>>> getAdminAuditLog({
    int page = 1,
  }) async {
    final uri = Uri.parse(
      '$baseUrl/admin/audit-log',
    ).replace(queryParameters: {'page': '$page'});
    final response = await http.get(uri, headers: await _authHeaders());
    if (response.statusCode == 200) {
      final data = _decodeResponse(response);
      if (data is Map && data['logs'] != null) {
        return (data['logs'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
      return (data as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
    }
    _throwFromResponse(response);
  }

  static Future<void> registerDeviceToken(
    String token, {
    String? platform,
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/devices/register'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'token': token,
        if (platform != null) 'platform': platform,
      }),
    );
    if (response.statusCode == 200 || response.statusCode == 201) return;
    _throwFromResponse(response);
  }

  static Future<void> unregisterDeviceToken({String? token}) async {
    final response = await http.delete(
      Uri.parse('$baseUrl/devices'),
      headers: await _authHeaders(),
      body: jsonEncode({if (token != null) 'token': token}),
    );
    if (response.statusCode == 200) return;
    _throwFromResponse(response);
  }
}
