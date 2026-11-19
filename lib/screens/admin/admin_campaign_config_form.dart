import 'dart:convert';

import 'package:flutter/material.dart';

import '../../services/incentive_api.dart';
import '../incentive/incentive_theme.dart';
import 'admin_rule_builder.dart';

const _audienceKinds = [
  'ALL_USERS',
  'BUYERS',
  'SELLERS',
  'NEW_USERS',
  'EXISTING_USERS',
  'FIRST_TIME_BUYERS',
  'ACTIVE_BUYERS',
  'INACTIVE_BUYERS',
  'NEW_SELLERS',
  'SOCIETIES',
  'CITIES',
  'REGIONS',
  'CUSTOM_SEGMENT',
];

const _triggers = [
  'USER_REGISTERED',
  'USER_BECAME_SELLER',
  'LISTING_PUBLISHED',
  'ORDER_QUALIFIED',
  'ORDER_CANCELLED',
  'ORDER_REJECTED',
  'REVIEW_SUBMITTED',
  'REFERRAL_ATTRIBUTED',
];

const _rewardTypes = ['FIXED_COUPON', 'PERCENTAGE_COUPON', 'PROMOTIONAL_CREDIT', 'POINTS'];
const _recipients = ['TRIGGER_USER', 'REFERRER', 'REFERRED', 'BUYER', 'SELLER'];

class AdminCampaignConfigForm extends StatefulWidget {
  const AdminCampaignConfigForm({
    super.key,
    required this.api,
    required this.campaignId,
    required this.category,
    required this.snapshot,
    this.readOnly = false,
  });

  final IncentiveApi api;
  final String campaignId;
  final String category;
  final Map<String, dynamic> snapshot;
  final bool readOnly;

  @override
  State<AdminCampaignConfigForm> createState() => _AdminCampaignConfigFormState();
}

class _AudienceDraft {
  _AudienceDraft({this.kind = 'ALL_USERS', this.payload = ''});
  String kind;
  String payload;
}

class _RewardDraft {
  _RewardDraft() {
    slot = TextEditingController(text: 'primary');
    amount = TextEditingController(text: '50');
    maxDiscount = TextEditingController();
    minOrder = TextEditingController();
    expiryDays = TextEditingController();
    usageLimit = TextEditingController();
  }

  late final TextEditingController slot;
  late final TextEditingController amount;
  late final TextEditingController maxDiscount;
  late final TextEditingController minOrder;
  late final TextEditingController expiryDays;
  late final TextEditingController usageLimit;
  String rewardType = 'FIXED_COUPON';
  String recipientRole = 'TRIGGER_USER';
  String stackingMode = '';
  bool requireAdminApproval = false;

  void dispose() {
    slot.dispose();
    amount.dispose();
    maxDiscount.dispose();
    minOrder.dispose();
    expiryDays.dispose();
    usageLimit.dispose();
  }
}

class _AdminCampaignConfigFormState extends State<AdminCampaignConfigForm> {
  final _budget = TextEditingController(text: '1000');
  final _maxCount = TextEditingController();
  final _maxAmount = TextEditingController();
  final _codeDays = TextEditingController();
  final _windowDays = TextEditingController();
  final _maxAttributions = TextEditingController();
  final _maxQualified = TextEditingController();
  final _buyerHours = TextEditingController();
  final _sellerHours = TextEditingController();
  final List<_AudienceDraft> _audiences = [_AudienceDraft()];
  final List<String> _selectedTriggers = ['USER_REGISTERED'];
  final List<_RewardDraft> _rewards = [_RewardDraft()];
  RuleNode _ruleRoot = RuleNode.group();
  String _eligibility = 'AUDIENCE_AND_TRIGGER_ONLY';
  bool _referralApproval = false;
  bool _busy = false;
  String? _error;

  bool get _referralCategory {
    return widget.category == 'REFERRAL' || widget.category == 'BUYER_ACQUISITION' || widget.category == 'SELLER_ACQUISITION';
  }

  @override
  void initState() {
    super.initState();
    _readSnapshot(widget.snapshot);
  }

  @override
  void dispose() {
    _budget.dispose();
    _maxCount.dispose();
    _maxAmount.dispose();
    _codeDays.dispose();
    _windowDays.dispose();
    _maxAttributions.dispose();
    _maxQualified.dispose();
    _buyerHours.dispose();
    _sellerHours.dispose();
    for (final reward in _rewards) {
      reward.dispose();
    }
    super.dispose();
  }

  void _readSnapshot(Map<String, dynamic> snapshot) {
    final audiences = snapshot['audiences'];
    if (audiences is List && audiences.isNotEmpty) {
      _audiences
        ..clear()
        ..addAll(audiences.whereType<Map>().map((row) {
          final payload = row['payload'];
          var text = '';
          if (payload is Map) {
            final values = payload['societyIds'] ?? payload['cityKeys'] ?? payload['regions'] ?? payload['segmentKey'];
            text = values is List ? values.join(', ') : values?.toString() ?? '';
          }
          return _AudienceDraft(kind: row['kind']?.toString() ?? 'ALL_USERS', payload: text);
        }));
    }
    final triggers = snapshot['triggers'];
    if (triggers is List && triggers.isNotEmpty) {
      _selectedTriggers
        ..clear()
        ..addAll(triggers.whereType<Map>().map((row) => row['eventType']?.toString() ?? '').where((value) => value.isNotEmpty));
    }
    _eligibility = snapshot['eligibility']?.toString() ?? _eligibility;
    if (snapshot['rules'] != null) {
      _ruleRoot = RuleNode.fromJson(snapshot['rules']);
    }
    final budget = snapshot['budget'];
    if (budget is Map) {
      _budget.text = budget['amountCap']?.toString() ?? _budget.text;
      _maxCount.text = budget['maxRewardCount']?.toString() ?? '';
      _maxAmount.text = budget['maxRewardAmount']?.toString() ?? '';
    }
    final rewards = snapshot['rewards'];
    if (rewards is List && rewards.isNotEmpty) {
      for (final reward in _rewards) {
        reward.dispose();
      }
      _rewards
        ..clear()
        ..addAll(rewards.whereType<Map>().map(_rewardFrom));
    }
    final policy = snapshot['referralPolicy'];
    if (policy is Map) {
      _codeDays.text = policy['codeExpiresInDays']?.toString() ?? '';
      _windowDays.text = policy['qualificationWindowDays']?.toString() ?? '';
      _maxAttributions.text = policy['maxAttributionsPerReferrer']?.toString() ?? '';
      _maxQualified.text = policy['maxQualifiedPerReferrer']?.toString() ?? '';
      _referralApproval = policy['requireAdminApproval'] == true;
      final buyer = policy['buyer'];
      final seller = policy['seller'];
      if (buyer is Map) _buyerHours.text = buyer['maxAccountAgeHours']?.toString() ?? '';
      if (seller is Map) _sellerHours.text = seller['maxAccountAgeHours']?.toString() ?? '';
    }
  }

  _RewardDraft _rewardFrom(Map row) {
    final reward = _RewardDraft();
    reward.slot.text = row['slot']?.toString() ?? 'primary';
    reward.amount.text = row['amount']?.toString() ?? '';
    reward.maxDiscount.text = row['maxDiscount']?.toString() ?? '';
    reward.minOrder.text = row['minOrder']?.toString() ?? '';
    reward.expiryDays.text = row['expiryDays']?.toString() ?? '';
    reward.usageLimit.text = row['usageLimit']?.toString() ?? '';
    reward.rewardType = row['rewardType']?.toString() ?? reward.rewardType;
    reward.recipientRole = row['recipientRole']?.toString() ?? reward.recipientRole;
    reward.stackingMode = row['stackingMode']?.toString() ?? '';
    reward.requireAdminApproval = row['requireAdminApproval'] == true;
    return reward;
  }

  Future<void> _save() async {
    if (_busy || widget.readOnly) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.putSection(widget.campaignId, 'audience', {
        'audiences': _audiences.map(_audienceBody).toList(),
      });
      await widget.api.putSection(widget.campaignId, 'triggers', {
        'triggers': _selectedTriggers.map((eventType) => {'eventType': eventType}).toList(),
      });
      await widget.api.putSection(widget.campaignId, 'rules', _rulesBody());
      await widget.api.putSection(widget.campaignId, 'budget', {
        'amountCap': _budget.text.trim(),
        'currency': 'INR',
        if (_maxCount.text.trim().isNotEmpty) 'maxRewardCount': int.tryParse(_maxCount.text.trim()),
        if (_maxAmount.text.trim().isNotEmpty) 'maxRewardAmount': _maxAmount.text.trim(),
      });
      await widget.api.putSection(widget.campaignId, 'rewards', {
        'rewards': _rewards.map(_rewardBody).toList(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Draft configuration saved')));
    } on IncentiveException catch (error) {
      _error = error.message;
    } on FormatException catch (error) {
      _error = error.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _savePolicy() async {
    if (_busy || widget.readOnly) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      int? number(String text) => text.trim().isEmpty ? null : int.tryParse(text.trim());
      await widget.api.putSection(widget.campaignId, 'referral-policy', {
        'referralPolicy': {
          'codeExpiresInDays': number(_codeDays.text),
          'qualificationWindowDays': number(_windowDays.text),
          'maxAttributionsPerReferrer': number(_maxAttributions.text),
          'maxQualifiedPerReferrer': number(_maxQualified.text),
          'requireAdminApproval': _referralApproval,
          'buyer': _buyerHours.text.trim().isEmpty ? null : {'maxAccountAgeHours': number(_buyerHours.text)},
          'seller': _sellerHours.text.trim().isEmpty ? null : {'maxAccountAgeHours': number(_sellerHours.text)},
        },
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Referral policy saved')));
    } on IncentiveException catch (error) {
      _error = error.message;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Map<String, dynamic> _audienceBody(_AudienceDraft row) {
    final ids = row.payload.split(',').map((item) => item.trim()).where((item) => item.isNotEmpty).toList();
    switch (row.kind) {
      case 'SOCIETIES':
        return {'kind': row.kind, 'payload': {'societyIds': ids}};
      case 'CITIES':
        return {'kind': row.kind, 'payload': {'cityKeys': ids}};
      case 'REGIONS':
        return {'kind': row.kind, 'payload': {'regions': ids}};
      case 'CUSTOM_SEGMENT':
        return {'kind': row.kind, 'payload': {'segmentKey': row.payload.trim()}};
      default:
        return {'kind': row.kind};
    }
  }

  Map<String, dynamic> _rulesBody() {
    if (_eligibility != 'RULES') return {'eligibility': _eligibility};
    final error = validateRuleTree(_ruleRoot, 1);
    if (error != null) throw FormatException(error);
    return {'eligibility': 'RULES', 'rules': _ruleRoot.toJson()};
  }

  Map<String, dynamic> _rewardBody(_RewardDraft reward) {
    String? text(TextEditingController controller) {
      final value = controller.text.trim();
      return value.isEmpty ? null : value;
    }

    return {
      'slot': reward.slot.text.trim(),
      'recipientRole': reward.recipientRole,
      'rewardType': reward.rewardType,
      'amount': reward.amount.text.trim(),
      if (text(reward.maxDiscount) != null) 'maxDiscount': text(reward.maxDiscount),
      if (text(reward.minOrder) != null) 'minOrder': text(reward.minOrder),
      if (text(reward.expiryDays) != null) 'expiryDays': int.tryParse(reward.expiryDays.text.trim()),
      if (text(reward.usageLimit) != null) 'usageLimit': int.tryParse(reward.usageLimit.text.trim()),
      if (reward.stackingMode.isNotEmpty) 'stackingMode': reward.stackingMode,
      'requireAdminApproval': reward.requireAdminApproval,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null) IncentiveNotice(message: _error!),
        const Text('Audience', style: TextStyle(fontWeight: FontWeight.w800)),
        for (var index = 0; index < _audiences.length; index++) ...[
          DropdownButtonFormField<String>(
            key: ValueKey('audience-$index-${_audiences[index].kind}'),
            initialValue: _audiences[index].kind,
            decoration: InputDecoration(labelText: 'Audience ${index + 1}'),
            items: [for (final kind in _audienceKinds) DropdownMenuItem(value: kind, child: Text(kind))],
            onChanged: widget.readOnly ? null : (value) => setState(() => _audiences[index].kind = value ?? _audiences[index].kind),
          ),
          if (_audiences[index].kind == 'SOCIETIES' || _audiences[index].kind == 'CITIES' || _audiences[index].kind == 'REGIONS' || _audiences[index].kind == 'CUSTOM_SEGMENT')
            TextFormField(
              initialValue: _audiences[index].payload,
              readOnly: widget.readOnly,
              decoration: InputDecoration(
                labelText: _audiences[index].kind == 'CUSTOM_SEGMENT' ? 'Segment key' : 'Ids, comma separated',
              ),
              onChanged: (value) => _audiences[index].payload = value,
            ),
        ],
        if (!widget.readOnly && _audiences.length < 20)
          TextButton(
            onPressed: () => setState(() => _audiences.add(_AudienceDraft(kind: 'BUYERS'))),
            child: const Text('Add audience'),
          ),
        const SizedBox(height: 8),
        const Text('Triggers', style: TextStyle(fontWeight: FontWeight.w800)),
        Wrap(
          spacing: 8,
          children: [
            for (final trigger in _triggers)
              FilterChip(
                label: Text(trigger),
                selected: _selectedTriggers.contains(trigger),
                onSelected: widget.readOnly
                    ? null
                    : (selected) => setState(() {
                          if (selected) {
                            _selectedTriggers.add(trigger);
                          } else {
                            _selectedTriggers.remove(trigger);
                          }
                        }),
              ),
          ],
        ),
        DropdownButtonFormField<String>(
          key: ValueKey('eligibility-$_eligibility'),
          initialValue: _eligibility,
          decoration: const InputDecoration(labelText: 'Eligibility'),
          items: const [
            DropdownMenuItem(value: 'AUDIENCE_AND_TRIGGER_ONLY', child: Text('Audience and trigger')),
            DropdownMenuItem(value: 'RULES', child: Text('Rules')),
          ],
          onChanged: widget.readOnly ? null : (value) => setState(() => _eligibility = value ?? _eligibility),
        ),
        if (_eligibility == 'RULES') ...[
          RuleBuilder(
            node: _ruleRoot,
            depth: 1,
            readOnly: widget.readOnly,
            onChanged: () => setState(() {}),
          ),
          const SizedBox(height: 8),
          const Text('Rule JSON', style: TextStyle(fontWeight: FontWeight.w700)),
          SelectableText(
            const JsonEncoder.withIndent('  ').convert(_ruleRoot.toJson()),
            style: const TextStyle(fontSize: 12, color: incentiveMuted),
          ),
        ],
        const SizedBox(height: 12),
        const Text('Rewards', style: TextStyle(fontWeight: FontWeight.w800)),
        for (final reward in _rewards) _rewardCard(reward),
        if (!widget.readOnly && _rewards.length < 10)
          TextButton(onPressed: () => setState(() => _rewards.add(_RewardDraft())), child: const Text('Add reward')),
        TextField(controller: _budget, readOnly: widget.readOnly, decoration: const InputDecoration(labelText: 'Budget cap (INR)')),
        TextField(controller: _maxCount, readOnly: widget.readOnly, decoration: const InputDecoration(labelText: 'Maximum reward count')),
        TextField(controller: _maxAmount, readOnly: widget.readOnly, decoration: const InputDecoration(labelText: 'Maximum reward amount')),
        if (!widget.readOnly) FilledButton(onPressed: _busy ? null : _save, child: const Text('Save configuration')),
        if (_referralCategory) ...[
          const SizedBox(height: 16),
          const Text('Referral policy', style: TextStyle(fontWeight: FontWeight.w800)),
          TextField(controller: _codeDays, readOnly: widget.readOnly, decoration: const InputDecoration(labelText: 'Code lifetime in days')),
          TextField(controller: _windowDays, readOnly: widget.readOnly, decoration: const InputDecoration(labelText: 'Qualification window in days')),
          TextField(controller: _maxAttributions, readOnly: widget.readOnly, decoration: const InputDecoration(labelText: 'Maximum attributions per referrer')),
          TextField(controller: _maxQualified, readOnly: widget.readOnly, decoration: const InputDecoration(labelText: 'Maximum qualified referrals per referrer')),
          TextField(controller: _buyerHours, readOnly: widget.readOnly, decoration: const InputDecoration(labelText: 'Buyer account age limit in hours')),
          TextField(controller: _sellerHours, readOnly: widget.readOnly, decoration: const InputDecoration(labelText: 'Seller account age limit in hours')),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Referral requires admin approval'),
            value: _referralApproval,
            onChanged: widget.readOnly ? null : (value) => setState(() => _referralApproval = value),
          ),
          if (!widget.readOnly) FilledButton(onPressed: _busy ? null : _savePolicy, child: const Text('Save referral policy')),
        ],
      ],
    );
  }

  Widget _rewardCard(_RewardDraft reward) {
    return IncentiveCard(
      child: Column(
        children: [
          TextField(controller: reward.slot, readOnly: widget.readOnly, decoration: const InputDecoration(labelText: 'Slot')),
          DropdownButtonFormField<String>(
            key: ValueKey('${reward.slot.text}-${reward.rewardType}'),
            initialValue: reward.rewardType,
            decoration: const InputDecoration(labelText: 'Reward type'),
            items: [for (final type in _rewardTypes) DropdownMenuItem(value: type, child: Text(incentiveRewardLabel(type)))],
            onChanged: widget.readOnly ? null : (value) => setState(() => reward.rewardType = value ?? reward.rewardType),
          ),
          DropdownButtonFormField<String>(
            key: ValueKey('${reward.slot.text}-${reward.recipientRole}'),
            initialValue: reward.recipientRole,
            decoration: const InputDecoration(labelText: 'Recipient'),
            items: [for (final role in _recipients) DropdownMenuItem(value: role, child: Text(role))],
            onChanged: widget.readOnly ? null : (value) => setState(() => reward.recipientRole = value ?? reward.recipientRole),
          ),
          TextField(controller: reward.amount, readOnly: widget.readOnly, decoration: const InputDecoration(labelText: 'Amount')),
          TextField(controller: reward.maxDiscount, readOnly: widget.readOnly, decoration: const InputDecoration(labelText: 'Maximum discount')),
          TextField(controller: reward.minOrder, readOnly: widget.readOnly, decoration: const InputDecoration(labelText: 'Minimum order')),
          TextField(controller: reward.expiryDays, readOnly: widget.readOnly, decoration: const InputDecoration(labelText: 'Expiry days')),
          TextField(controller: reward.usageLimit, readOnly: widget.readOnly, decoration: const InputDecoration(labelText: 'Usage limit')),
          DropdownButtonFormField<String>(
            key: ValueKey('${reward.slot.text}-stack-${reward.stackingMode}'),
            initialValue: reward.stackingMode,
            decoration: const InputDecoration(labelText: 'Reward stacking'),
            items: const [
              DropdownMenuItem(value: '', child: Text('Campaign default')),
              DropdownMenuItem(value: 'STACK', child: Text('STACK')),
              DropdownMenuItem(value: 'EXCLUSIVE', child: Text('EXCLUSIVE')),
              DropdownMenuItem(value: 'FIRST_MATCH', child: Text('FIRST_MATCH')),
            ],
            onChanged: widget.readOnly ? null : (value) => setState(() => reward.stackingMode = value ?? ''),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Require admin approval'),
            value: reward.requireAdminApproval,
            onChanged: widget.readOnly ? null : (value) => setState(() => reward.requireAdminApproval = value),
          ),
          if (!widget.readOnly && _rewards.length > 1)
            TextButton(
              onPressed: () => setState(() {
                reward.dispose();
                _rewards.remove(reward);
              }),
              child: const Text('Remove reward'),
            ),
        ],
      ),
    );
  }
}
