import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'session_service.dart';

class TokenExpiredException implements Exception {
  final String message;
  TokenExpiredException(this.message);
  @override
  String toString() => message;
}

class ApiService {
  static String get baseUrl {
    if (kIsWeb) {
      final host = Uri.base.host;
      final port = 3000;
      final scheme = Uri.base.scheme;
      return '$scheme://$host:$port';
    }
    if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:3000';
    return 'http://127.0.0.1:3000';
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

  static dynamic _decodeResponse(http.Response response) {
    if (response.body.isEmpty) return null;
    return jsonDecode(response.body);
  }

  static Never _throwFromResponse(http.Response response) {
    final body = _decodeResponse(response);
    final message = body is Map && body['error'] != null
        ? body['error'].toString()
        : response.body;

    if (response.statusCode == 401 && body is Map && body['code'] == 'TOKEN_EXPIRED') {
      throw TokenExpiredException(message);
    }

    throw Exception(message);
  }

  static Future<Map<String, dynamic>> firebaseLogin(String firebaseToken) async {
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
      if (data['token'] != null) {
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
        return data
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
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
        if (weightUnit != null && weightUnit.isNotEmpty) 'weightUnit': weightUnit,
        if (weightValue != null && weightValue.isNotEmpty) 'weightValue': weightValue,
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
  }) async {
    final response = await http.post(
      Uri.parse('$baseUrl/orders'),
      headers: await _authHeaders(),
      body: jsonEncode({
        'societyId': societyId,
        'paymentMethod': paymentMethod,
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

  static Future<List<Map<String, dynamic>>> getListingReviews(
    String listingId,
  ) async {
    final response =
        await http.get(Uri.parse('$baseUrl/reviews/listing/$listingId'));

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
    final uri =
        Uri.parse('$baseUrl/admin/users').replace(queryParameters: query);
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
    final uri =
        Uri.parse('$baseUrl/admin/listings').replace(queryParameters: query);
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
    final uri =
        Uri.parse('$baseUrl/admin/orders').replace(queryParameters: query);
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
    final uri = Uri.parse('$baseUrl/admin/reviews')
        .replace(queryParameters: {'page': '$page'});
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
    final uri = Uri.parse('$baseUrl/admin/audit-log')
        .replace(queryParameters: {'page': '$page'});
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
}
