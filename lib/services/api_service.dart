import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import 'session_service.dart';

class ApiService {
  static String get baseUrl {
    if (kIsWeb) return 'http://127.0.0.1:3000';
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
    final userId = await SessionService.getUserId();
    return {
      'Content-Type': 'application/json',
      if (userId != null) 'x-user-id': userId,
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
    throw Exception(message);
  }

  static Future<Map<String, dynamic>> loginUser(String phone) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'phone': phone}),
    );

    if (response.statusCode == 200 || response.statusCode == 201) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> getUser(String userId) async {
    final response = await http.get(Uri.parse('$baseUrl/auth/users/$userId'));

    if (response.statusCode == 200) {
      return Map<String, dynamic>.from(_decodeResponse(response) as Map);
    }
    _throwFromResponse(response);
  }

  static Future<Map<String, dynamic>> updateUserProfile(
    String userId, {
    String? name,
    String? role,
    String? societyId,
    String? flatId,
  }) async {
    final response = await http.patch(
      Uri.parse('$baseUrl/auth/users/$userId/profile'),
      headers: await _authHeaders(),
      body: jsonEncode({
        if (name != null) 'name': name,
        if (role != null) 'role': role,
        if (societyId != null) 'societyId': societyId,
        if (flatId != null) 'flatId': flatId,
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
  }) async {
    final query = <String, String>{'societyId': societyId};
    if (sellerId != null) query['sellerId'] = sellerId;
    if (search != null && search.trim().isNotEmpty) {
      query['search'] = search.trim();
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
}
