import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/incentive_api.dart';
import 'incentive_theme.dart';

class IncentiveAccountScreen extends StatefulWidget {
  const IncentiveAccountScreen({
    super.key,
    required this.audience,
    this.api,
  });

  /// BUYER or SELLER. The server still decides which code the signed-in user may hold.
  final String audience;
  final IncentiveApi? api;

  @override
  State<IncentiveAccountScreen> createState() => _IncentiveAccountScreenState();
}

class _IncentiveAccountScreenState extends State<IncentiveAccountScreen> {
  late final IncentiveApi _api = widget.api ?? IncentiveApi();
  bool _loading = true;
  bool _busy = false;
  String? _error;
  bool _codesOff = false;
  Map<String, bool> _flags = const {};
  List<Map<String, dynamic>> _codes = const [];
  List<Map<String, dynamic>> _referrals = const [];
  List<Map<String, dynamic>> _rewards = const [];
  List<Map<String, dynamic>> _history = const [];
  String _creditBalance = '0.00';
  String _pointsBalance = '0.00';
  List<Map<String, dynamic>> _offers = const [];
  String? _offerReason;
  List<Map<String, dynamic>> _leaders = const [];
  String? _expiryNotice;

  bool get _seller => widget.audience == 'SELLER';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _codesOff = false;
    });
    try {
      final flags = await _api.flags();
      List<Map<String, dynamic>> codes = const [];
      List<Map<String, dynamic>> referrals = const [];
      var codesOff = flags['referral'] != true || flags['master'] != true;
      if (!codesOff) {
        try {
          codes = await _api.myCodes();
          referrals = await _api.myReferrals();
        } on IncentiveException catch (error) {
          if (error.code == 'REFERRAL_DISABLED' || error.statusCode == 403) {
            codesOff = true;
          } else {
            rethrow;
          }
        }
      }
      final rewardsBody = await _api.myRewards();
      final offersBody = await _api.myOffers();
      List<Map<String, dynamic>> leaders = const [];
      if (!codesOff) {
        try {
          leaders = await _api.leaderboard(audience: widget.audience);
        } on IncentiveException catch (error) {
          if (error.code != 'REFERRAL_DISABLED' && error.statusCode != 403) rethrow;
        }
      }
      final historyBody = await _api.myRewardHistory();
      final rewardRows = rewardsBody['rewards'];
      final offerRows = offersBody['offers'];
      final historyRows = historyBody['entries'];
      final balances = rewardsBody['balances'];
      if (!mounted) return;
      setState(() {
        _flags = flags;
        _codes = codes;
        _referrals = referrals;
        _codesOff = codesOff;
        _rewards = rewardRows is List ? rewardRows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList() : const [];
        _offers = offerRows is List ? offerRows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList() : const [];
        _offerReason = offersBody['reason']?.toString();
        _history = historyRows is List ? historyRows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList() : const [];
        _creditBalance = balances is Map ? balances['promotionalCredit']?.toString() ?? '0.00' : '0.00';
        _pointsBalance = balances is Map ? balances['points']?.toString() ?? '0.00' : '0.00';
        _leaders = leaders;
        _expiryNotice = _expiringNotice(_rewards);
        _loading = false;
      });
    } on IncentiveException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.isDenied ? 'You do not have access to this referral information.' : error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load referrals. Please try again.';
      });
    }
  }

  Future<void> _generate() async {
    if (_busy || _codesOff) return;
    setState(() => _busy = true);
    try {
      await _api.createCode(audience: widget.audience);
      await _load();
    } on IncentiveException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String? _expiringNotice(List<Map<String, dynamic>> rewards) {
    final soon = rewards.where((row) {
      final at = DateTime.tryParse(row['expiresAt']?.toString() ?? '');
      if (at == null) return false;
      final status = row['status']?.toString();
      if (status == 'EXPIRED' || status == 'REDEEMED' || status == 'REJECTED') return false;
      final days = at.difference(DateTime.now()).inDays;
      return days >= 0 && days <= 7;
    }).length;
    if (soon == 0) return null;
    return soon == 1 ? '1 reward expires within 7 days.' : '$soon rewards expire within 7 days.';
  }

  String _shareText(Map<String, dynamic> code) {
    final value = code['url']?.toString();
    if (value == null || value.isEmpty) return 'Join me on SocietyEats with referral code ${code['code']}';
    return 'Join me on SocietyEats: $value';
  }

  Future<void> _shareSheet(Map<String, dynamic> code) async {
    try {
      await Share.share(_shareText(code));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('The share sheet is unavailable. Copy the code instead.')));
    }
  }

  Future<void> _share(Map<String, dynamic> code, {required bool whatsApp}) async {
    final text = _shareText(code);
    final uri = whatsApp
        ? Uri.parse('https://wa.me/?text=${Uri.encodeComponent(text)}')
        : Uri.parse('mailto:?subject=${Uri.encodeComponent('SocietyEats referral')}&body=${Uri.encodeComponent(text)}');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the share app. Copy the code instead.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = _codes.where((row) => row['audience'] == widget.audience || row['audience'] == 'ANY').toList();
    final pending = _referrals.where((row) => row['status'] != 'QUALIFIED' && row['status'] != 'DISQUALIFIED' && row['status'] != 'EXPIRED').length;
    final qualified = _referrals.where((row) => row['status'] == 'QUALIFIED').length;
    return Scaffold(
      backgroundColor: incentiveCanvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: incentiveInk,
        elevation: 0,
        title: Text(_seller ? 'Seller referrals' : 'Referrals & rewards'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: incentiveGreen))
          : RefreshIndicator(
              color: incentiveGreen,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: [
                  if (_error != null) IncentiveNotice(message: _error!, onRetry: _load),
                  if (_expiryNotice != null) IncentiveNotice(message: _expiryNotice!),
                  if (_codesOff)
                    const IncentiveNotice(
                      message: 'Referral codes are switched off. Your code, share link, and referral list appear here when an administrator turns referral on.',
                    ),
                  if (!_codesOff && mine.isEmpty)
                    IncentiveCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_seller ? 'Seller referral code' : 'My referral code', style: const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          const Text('You do not have a code yet.'),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _busy ? null : _generate,
                            child: const Text('Generate code'),
                          ),
                        ],
                      ),
                    ),
                  for (final code in mine) _codeCard(code),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _stat('Pending', '$pending'),
                      _stat('Qualified', '$qualified'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Referrals', style: TextStyle(fontWeight: FontWeight.w800, color: incentiveInk)),
                  const SizedBox(height: 8),
                  if (_referrals.isEmpty)
                    const IncentiveNotice(message: 'No referrals yet.')
                  else
                    for (final row in _referrals) _referralCard(row),
                  const SizedBox(height: 16),
                  const Text('Balances', style: TextStyle(fontWeight: FontWeight.w800, color: incentiveInk)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _stat('Promotional credit', _creditBalance),
                      _stat('Points', _pointsBalance),
                    ],
                  ),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Promotional credit and points are not cash and cannot be withdrawn.',
                      style: TextStyle(color: incentiveMuted, fontSize: 12),
                    ),
                  ),
                  const Text('Leaderboard', style: TextStyle(fontWeight: FontWeight.w800, color: incentiveInk)),
                  const SizedBox(height: 8),
                  if (_leaders.isEmpty)
                    const IncentiveNotice(message: 'No public leaderboard is available while referrals are off.')
                  else
                    for (final leader in _leaders)
                      IncentiveCard(child: Text('${leader['displayName'] ?? 'Member'} · ${leader['qualified'] ?? 0} qualified')),
                  const SizedBox(height: 16),
                  const Text('Offers', style: TextStyle(fontWeight: FontWeight.w800, color: incentiveInk)),
                  const SizedBox(height: 8),
                  if (_offerReason == 'ENGINE_OFF' || _flags['master'] != true)
                    const IncentiveNotice(
                      message: 'Incentive offers are off. Completed orders do not earn a reward until an administrator turns the programme on.',
                    )
                  else if (_offers.isEmpty)
                    const IncentiveNotice(message: 'No offers are active for this account.')
                  else
                    for (final offer in _offers) _offerCard(offer),
                  const SizedBox(height: 16),
                  const Text('My rewards', style: TextStyle(fontWeight: FontWeight.w800, color: incentiveInk)),
                  const SizedBox(height: 8),
                  IncentiveNotice(
                    message: _seller
                        ? 'This screen shows your own rewards. Buyer rewards on an order stay on the buyer account.'
                        : 'A reward appears here only after SocietyEats confirms it. Pending, accepted, and ready orders have not earned one. The seller marks the order completed, and the payment still has to be confirmed.',
                  ),
                  const SizedBox(height: 8),
                  if (_rewards.isEmpty)
                    const IncentiveNotice(message: 'No rewards yet.')
                  else
                    for (final reward in _rewards) _rewardCard(reward),
                  const Text('Reward history', style: TextStyle(fontWeight: FontWeight.w800, color: incentiveInk)),
                  const SizedBox(height: 8),
                  if (_history.isEmpty)
                    const IncentiveNotice(message: 'No reward history yet.')
                  else
                    for (final entry in _history)
                      IncentiveCard(
                        child: Text(
                          '${entry['entryType']} ${entry['amount']} · ${incentiveRewardLabel(entry['rewardType'])}\n${incentiveWhen(entry['createdAt'])}\n${entry['idempotencyKey']}',
                        ),
                      ),
                  if (_flags.isNotEmpty)
                    Text(
                      'Referral ${(_flags['referral'] == true) ? 'on' : 'off'}',
                      style: const TextStyle(color: incentiveMuted, fontSize: 12),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _stat(String label, String value) {
    return SizedBox(
      width: 140,
      child: IncentiveCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: incentiveGreen)),
            Text(label, style: const TextStyle(color: incentiveMuted)),
          ],
        ),
      ),
    );
  }

  Widget _codeCard(Map<String, dynamic> code) {
    final value = code['code']?.toString() ?? '';
    final link = code['url']?.toString();
    return IncentiveCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_seller ? 'Seller referral code' : 'My referral code', style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          SelectableText(value, style: const TextStyle(fontSize: 18, letterSpacing: 1.2, fontWeight: FontWeight.w700)),
          if (link == null || link.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('A share link is not configured. You can still copy the code.', style: TextStyle(color: incentiveMuted)),
            )
          else
            Padding(padding: const EdgeInsets.only(top: 6), child: SelectableText(link)),
          Wrap(
            spacing: 8,
            children: [
              TextButton(onPressed: () => copyIncentiveText(context, value, 'Code'), child: const Text('Copy code')),
              if (link != null && link.isNotEmpty)
                TextButton(onPressed: () => copyIncentiveText(context, link, 'Link'), child: const Text('Copy link')),
              TextButton(onPressed: () => _share(code, whatsApp: true), child: const Text('WhatsApp')),
              TextButton(onPressed: () => _shareSheet(code), child: const Text('Share sheet')),
              TextButton(onPressed: () => _share(code, whatsApp: false), child: const Text('Email')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _referralCard(Map<String, dynamic> row) {
    final qualified = row['status'] == 'QUALIFIED';
    return IncentiveCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${row['displayName'] ?? 'New member'} · ${row['status']}', style: const TextStyle(fontWeight: FontWeight.w700)),
          Text('${row['acquisitionKind'] ?? ''} · ${row['role'] ?? ''} · ${incentiveWhen(row['attributedAt'])}'),
          if (_seller || row['acquisitionKind'] == 'SELLER_ACQUISITION') ...[
            const SizedBox(height: 6),
            Text(_milestone('Seller activation', row['sellerActivated'] == true)),
            Text(_milestone('First listing', row['listingPublished'] == true)),
            Text(_milestone('First qualifying sale', row['orderQualified'] == true)),
          ],
          if (qualified)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Qualified', style: TextStyle(color: incentiveGreen, fontWeight: FontWeight.w700)),
            ),
          if (row['qualificationNote'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(row['qualificationNote'].toString()),
            ),
        ],
      ),
    );
  }

  Widget _offerCard(Map<String, dynamic> offer) {
    final rewards = offer['rewards'];
    final summary = rewards is List && rewards.isNotEmpty
        ? rewards.whereType<Map>().map((row) => incentiveRewardLabel(row['rewardType'])).join(', ')
        : 'Reward details are on the campaign';
    final ends = offer['endsAt'] == null ? '' : '\nEnds ${incentiveWhen(offer['endsAt'])}';
    return IncentiveCard(
      child: Text(
        '${offer['name'] ?? 'Offer'}\n$summary$ends\n${offer['qualifiesWhen'] ?? ''}',
      ),
    );
  }

  String _milestone(String label, bool done) => done ? '$label complete' : '$label pending';

  Widget _rewardCard(Map<String, dynamic> reward) {
    final type = reward['rewardType']?.toString();
    final cashNote = type == 'PROMOTIONAL_CREDIT' || type == 'POINTS' ? '\nNot cash and cannot be withdrawn.' : '';
    final expiry = reward['expiresAt'] == null ? '' : '\nExpires ${incentiveWhen(reward['expiresAt'])}';
    return IncentiveCard(
      child: Text(
        '${incentiveRewardLabel(type)} · ${reward['status']} · ${reward['amount'] ?? '—'} ${reward['currency'] ?? ''}$expiry$cashNote',
      ),
    );
  }
}
