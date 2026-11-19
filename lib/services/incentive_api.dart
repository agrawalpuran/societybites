import 'dart:convert';

import 'api_service.dart';

/// Caller-supplied transport so screens can be tested without a server.
typedef IncentiveTransport = Future<dynamic> Function(
  String method,
  String path, {
  Object? body,
  Map<String, String>? query,
});

class IncentiveException implements Exception {
  IncentiveException(this.message, {this.statusCode, this.code});

  final String message;
  final int? statusCode;
  final String? code;

  bool get isDenied => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

const _incentiveFlagKeys = [
  'master',
  'issuance',
  'redemption',
  'referral',
  'buyerReferral',
  'sellerReferral',
  'promotional',
];

class IncentiveFlagView {
  const IncentiveFlagView({required this.effective, required this.stored});

  final Map<String, bool> effective;
  final Map<String, bool> stored;
}

Map<String, bool> _incentiveBoolMap(Object? source) {
  final map = source is Map ? source : const {};
  return {for (final key in _incentiveFlagKeys) key: map[key] == true};
}

IncentiveFlagView _parseFlagView(dynamic body) {
  final source = body is Map ? body : const {};
  final effective = _incentiveBoolMap(source);
  final storedSource = source['stored'];
  return IncentiveFlagView(
    effective: effective,
    stored: storedSource is Map ? _incentiveBoolMap(storedSource) : effective,
  );
}

class IncentiveApi {
  IncentiveApi({IncentiveTransport? transport}) : _transport = transport ?? _send;

  final IncentiveTransport _transport;

  static Future<dynamic> _send(
    String method,
    String path, {
    Object? body,
    Map<String, String>? query,
  }) async {
    final headers = await ApiService.captureAuthHeaders();
    final uri = Uri.parse(ApiService.absoluteUrl(path)).replace(
      queryParameters: query == null || query.isEmpty ? null : query,
    );
    final encoded = body == null ? null : jsonEncode(body);
    final response = switch (method) {
      'POST' => await http.post(uri, headers: headers, body: encoded),
      'PUT' => await http.put(uri, headers: headers, body: encoded),
      'PATCH' => await http.patch(uri, headers: headers, body: encoded),
      _ => await http.get(uri, headers: headers),
    };
    final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }
    final message = decoded is Map && decoded['error'] != null
        ? decoded['error'].toString()
        : 'Incentive request failed';
    final code = decoded is Map ? decoded['code']?.toString() : null;
    throw IncentiveException(message, statusCode: response.statusCode, code: code);
  }

  Future<Map<String, bool>> flags() async {
    return (await flagView()).effective;
  }

  /// Effective switches plus the stored on/off value. A stored switch can be on while Master keeps it off.
  Future<IncentiveFlagView> flagView() async {
    final body = await _transport('GET', '/incentive/flags');
    return _parseFlagView(body);
  }

  /// Super admin only. `key` is master, referral, buyerReferral, or sellerReferral.
  Future<IncentiveFlagView> setFlag({required String key, required bool enabled}) async {
    final saved = await _transport('PUT', '/incentive/admin/flags', body: {'key': key, 'enabled': enabled});
    return _parseFlagView(saved);
  }

  Future<List<Map<String, dynamic>>> campaigns() async {
    final body = await _transport('GET', '/incentive/admin/campaigns');
    if (body is! List) return const [];
    return body.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<Map<String, dynamic>> campaign(String id) async {
    final body = await _transport('GET', '/incentive/admin/campaigns/$id');
    return body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> createCampaign(Map<String, dynamic> body) async {
    final saved = await _transport('POST', '/incentive/admin/campaigns', body: body);
    return saved is Map ? Map<String, dynamic>.from(saved) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> updateCampaign(String id, Map<String, dynamic> body) async {
    final saved = await _transport('PATCH', '/incentive/admin/campaigns/$id', body: body);
    return saved is Map ? Map<String, dynamic>.from(saved) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> putSection(String id, String section, Map<String, dynamic> body) async {
    final saved = await _transport('PUT', '/incentive/admin/campaigns/$id/$section', body: body);
    return saved is Map ? Map<String, dynamic>.from(saved) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> simulate(String id, Map<String, dynamic> attributes) async {
    final saved = await _transport(
      'POST',
      '/incentive/admin/campaigns/$id/simulate',
      body: {'attributes': attributes},
    );
    return saved is Map ? Map<String, dynamic>.from(saved) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> duplicateCampaign(String id, String name) async {
    final saved = await _transport('POST', '/incentive/admin/campaigns/$id/duplicate', body: {'name': name});
    return saved is Map ? Map<String, dynamic>.from(saved) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> campaignPerformance(String id, {String? from, String? to}) async {
    final body = await _transport(
      'GET',
      '/incentive/admin/campaigns/$id/performance',
      query: {
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
      },
    );
    return body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> referralAnalytics({String? campaignId, String? from, String? to}) async {
    final body = await _transport(
      'GET',
      '/incentive/admin/referral-analytics',
      query: {
        if (campaignId != null && campaignId.isNotEmpty) 'campaignId': campaignId,
        if (from != null && from.isNotEmpty) 'from': from,
        if (to != null && to.isNotEmpty) 'to': to,
      },
    );
    return body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> rewardReport({String? campaignId, String? status, String? rewardType, String? cursor}) async {
    final body = await _transport(
      'GET',
      '/incentive/admin/reward-report',
      query: {
        if (campaignId != null && campaignId.isNotEmpty) 'campaignId': campaignId,
        if (status != null && status.isNotEmpty) 'status': status,
        if (rewardType != null && rewardType.isNotEmpty) 'rewardType': rewardType,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        'limit': '20',
      },
    );
    return body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> auditLog({String? campaignId, String? action, String? cursor}) async {
    final body = await _transport(
      'GET',
      '/incentive/admin/audit',
      query: {
        if (campaignId != null && campaignId.isNotEmpty) 'campaignId': campaignId,
        if (action != null && action.isNotEmpty) 'action': action,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
    );
    return body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> riskReport({String? campaignId}) async {
    final body = await _transport(
      'GET',
      '/incentive/admin/risk',
      query: {if (campaignId != null && campaignId.isNotEmpty) 'campaignId': campaignId},
    );
    return body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> eventPage({String? status, String? type, String? cursor}) async {
    final body = await _transport(
      'GET',
      '/incentive/admin/events',
      query: {
        'limit': '20',
        if (status != null && status.isNotEmpty) 'status': status,
        if (type != null && type.isNotEmpty) 'type': type,
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
      },
    );
    return body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> replayEvent(String id) async {
    final saved = await _transport('POST', '/incentive/admin/events/$id/replay');
    return saved is Map ? Map<String, dynamic>.from(saved) : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> leaderboard({String? audience}) async {
    final body = await _transport(
      'GET',
      '/incentive/referrals/leaderboard',
      query: {if (audience != null && audience.isNotEmpty) 'audience': audience},
    );
    final rows = body is Map ? body['leaders'] : null;
    if (rows is! List) return const [];
    return rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<Map<String, dynamic>> lifecycle(String id, String action) async {
    final saved = await _transport('POST', '/incentive/admin/campaigns/$id/$action');
    return saved is Map ? Map<String, dynamic>.from(saved) : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> events({String? status}) async {
    final body = await _transport(
      'GET',
      '/incentive/admin/events',
      query: {
        if (status != null && status.isNotEmpty) 'status': status,
        'limit': '20',
      },
    );
    final rows = body is Map ? body['events'] : null;
    if (rows is! List) return const [];
    return rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<List<Map<String, dynamic>>> adminReferrals({
    String? status,
    String? acquisitionKind,
  }) async {
    final body = await _transport(
      'GET',
      '/incentive/admin/referrals',
      query: {
        if (status != null && status.isNotEmpty) 'status': status,
        if (acquisitionKind != null && acquisitionKind.isNotEmpty) 'acquisitionKind': acquisitionKind,
      },
    );
    final rows = body is Map ? body['referrals'] : null;
    if (rows is! List) return const [];
    return rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<Map<String, dynamic>> referralDecision(String id, String action, {String? reason}) async {
    final saved = await _transport(
      'POST',
      '/incentive/admin/referrals/$id/$action',
      body: {if (reason != null && reason.isNotEmpty) 'reason': reason},
    );
    return saved is Map ? Map<String, dynamic>.from(saved) : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> rewards({String? status}) async {
    final body = await _transport(
      'GET',
      '/incentive/admin/rewards',
      query: {if (status != null && status.isNotEmpty) 'status': status},
    );
    final rows = body is Map ? body['rewards'] : null;
    if (rows is! List) return const [];
    return rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<Map<String, dynamic>> rewardDetail(String id) async {
    final body = await _transport('GET', '/incentive/admin/rewards/$id');
    return body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> decideReward(String id, String action, {String? reason}) async {
    final saved = await _transport(
      'POST',
      '/incentive/admin/rewards/$id/$action',
      body: {if (reason != null && reason.isNotEmpty) 'reason': reason},
    );
    final reward = saved is Map ? saved['reward'] : null;
    return reward is Map ? Map<String, dynamic>.from(reward) : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> myCodes() async {
    final body = await _transport('GET', '/incentive/referral-codes');
    final rows = body is Map ? body['codes'] : null;
    if (rows is! List) return const [];
    return rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<Map<String, dynamic>> createCode({
    required String audience,
    String? campaignId,
  }) async {
    final saved = await _transport(
      'POST',
      '/incentive/referral-codes',
      body: {
        'audience': audience,
        if (campaignId != null && campaignId.isNotEmpty) 'campaignId': campaignId,
      },
    );
    return saved is Map ? Map<String, dynamic>.from(saved) : <String, dynamic>{};
  }

  Future<List<Map<String, dynamic>>> myReferrals() async {
    final body = await _transport('GET', '/incentive/referrals');
    final rows = body is Map ? body['referrals'] : null;
    if (rows is! List) return const [];
    return rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Future<Map<String, dynamic>> overview() async {
    final body = await _transport('GET', '/incentive/admin/overview');
    return body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> ledger({
    String? cursor,
    String? entryType,
    String? userId,
    String? rewardType,
    String? rewardId,
  }) async {
    final body = await _transport(
      'GET',
      '/incentive/admin/ledger',
      query: {
        'limit': '20',
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        if (entryType != null && entryType.isNotEmpty) 'entryType': entryType,
        if (userId != null && userId.isNotEmpty) 'userId': userId,
        if (rewardType != null && rewardType.isNotEmpty) 'rewardType': rewardType,
        if (rewardId != null && rewardId.isNotEmpty) 'rewardId': rewardId,
      },
    );
    return body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
  }

  /// Signed-in offers. The server uses the JWT role and ignores a client audience.
  Future<Map<String, dynamic>> myOffers() async {
    final body = await _transport('GET', '/incentive/offers');
    return body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
  }

  /// Rewards for the signed-in user. The server ignores any user id in the query.
  Future<Map<String, dynamic>> myRewards({String? status, String? rewardType}) async {
    final body = await _transport(
      'GET',
      '/incentive/rewards',
      query: {
        if (status != null && status.isNotEmpty) 'status': status,
        if (rewardType != null && rewardType.isNotEmpty) 'rewardType': rewardType,
      },
    );
    return body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> myRewardHistory({
    String? cursor,
    String? rewardType,
    String? entryType,
  }) async {
    final body = await _transport(
      'GET',
      '/incentive/rewards/history',
      query: {
        'limit': '20',
        if (cursor != null && cursor.isNotEmpty) 'cursor': cursor,
        if (rewardType != null && rewardType.isNotEmpty) 'rewardType': rewardType,
        if (entryType != null && entryType.isNotEmpty) 'entryType': entryType,
      },
    );
    return body is Map ? Map<String, dynamic>.from(body) : <String, dynamic>{};
  }
}
