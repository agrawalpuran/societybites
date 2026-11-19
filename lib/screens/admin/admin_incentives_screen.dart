import 'package:flutter/material.dart';

import '../../services/incentive_api.dart';
import '../incentive/incentive_theme.dart';
import 'admin_campaign_editor.dart';
import 'admin_incentive_insights.dart';

class AdminIncentivesScreen extends StatefulWidget {
  const AdminIncentivesScreen({
    super.key,
    required this.isSuperAdmin,
    this.api,
  });

  final bool isSuperAdmin;
  final IncentiveApi? api;

  @override
  State<AdminIncentivesScreen> createState() => _AdminIncentivesScreenState();
}

class _AdminIncentivesScreenState extends State<AdminIncentivesScreen> {
  late final IncentiveApi _api = widget.api ?? IncentiveApi();
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _campaigns = const [];
  List<Map<String, dynamic>> _referrals = const [];
  List<Map<String, dynamic>> _rewards = const [];
  Map<String, bool> _flags = const {};
  Map<String, bool> _stored = const {};
  Map<String, dynamic> _overview = const {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.campaigns(),
        _api.adminReferrals(),
        _api.rewards(),
        _api.flagView(),
        _api.overview(),
      ]);
      if (!mounted) return;
      final view = results[3] as IncentiveFlagView;
      setState(() {
        _campaigns = results[0] as List<Map<String, dynamic>>;
        _referrals = results[1] as List<Map<String, dynamic>>;
        _rewards = results[2] as List<Map<String, dynamic>>;
        _flags = view.effective;
        _stored = view.stored;
        _overview = results[4] as Map<String, dynamic>;
        _loading = false;
      });
    } on IncentiveException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _run(Future<void> Function() work) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await work();
      await _load();
    } on IncentiveException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleFlag(String key, String label, bool enabled) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(enabled ? 'Turn $label on?' : 'Turn $label off?'),
        content: Text(_flagDialogCopy(key, enabled)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: incentiveGreen, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(enabled ? 'Turn on' : 'Turn off'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _run(() async {
      await _api.setFlag(key: key, enabled: enabled);
    });
  }

  String _flagDialogCopy(String key, bool enabled) {
    if (enabled) {
      return 'A referral code still needs Master, Referral, and the buyer or seller switch. Turning this on does not issue a reward.';
    }
    switch (key) {
      case 'referral':
        return 'Buyers and sellers cannot create or view new referral codes. Existing codes stay stored.';
      case 'buyerReferral':
        return 'Buyers cannot create or view a new referral code. Existing codes stay stored.';
      case 'sellerReferral':
        return 'Sellers cannot create or view a new referral code. Existing codes stay stored.';
      default:
        return 'New referral codes stop. Codes and rewards already stored stay in place.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final showSettings = widget.isSuperAdmin;
    final tabs = <Tab>[
      const Tab(text: 'Overview'),
      const Tab(text: 'Campaigns'),
      const Tab(text: 'Referrals'),
      const Tab(text: 'Approvals'),
      const Tab(text: 'Coupons & credits'),
      const Tab(text: 'Ledger'),
      if (showSettings) const Tab(text: 'Settings'),
      const Tab(text: 'Events'),
      const Tab(text: 'Audit'),
      const Tab(text: 'Referral analytics'),
      const Tab(text: 'Reward report'),
      const Tab(text: 'Risk'),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        backgroundColor: incentiveCanvas,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: incentiveInk,
          elevation: 0,
          title: const Text('Incentives & Rewards'),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: tabs,
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: incentiveGreen))
            : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: IncentiveNotice(message: _error!, onRetry: _load),
                  )
                : TabBarView(
                    children: [
                      _Overview(overview: _overview),
                      _Campaigns(
                        campaigns: _campaigns,
                        isSuperAdmin: widget.isSuperAdmin,
                        busy: _busy,
                        api: _api,
                        onChanged: _load,
                      ),
                      _Referrals(
                        referrals: _referrals,
                        isSuperAdmin: widget.isSuperAdmin,
                        busy: _busy,
                        onDecision: (id, action, reason) => _run(() async {
                          await _api.referralDecision(id, action, reason: reason);
                        }),
                      ),
                      _Approvals(
                        rewards: _rewards.where((row) => row['status'] == 'PENDING_APPROVAL').toList(),
                        isSuperAdmin: widget.isSuperAdmin,
                        busy: _busy,
                        onDecision: (id, action, reason) => _run(() async {
                          await _api.decideReward(id, action, reason: reason);
                        }),
                      ),
                      _RewardBoard(rewards: _rewards),
                      _Ledger(api: _api),
                      if (showSettings)
                        _Settings(
                          flags: _flags,
                          stored: _stored,
                          busy: _busy,
                          onToggle: _toggleFlag,
                        ),
                      EventMonitorTab(api: _api, isSuperAdmin: widget.isSuperAdmin),
                      AuditLogTab(api: _api),
                      ReferralAnalyticsTab(api: _api),
                      RewardReportTab(api: _api),
                      RiskTab(api: _api),
                    ],
                  ),
      ),
    );
  }
}

class _Overview extends StatelessWidget {
  const _Overview({required this.overview});

  final Map<String, dynamic> overview;

  String _count(String group, String key) {
    final source = overview[group];
    if (source is! Map) return '0';
    final value = source[key];
    if (value is num) return value.toInt().toString();
    return value?.toString() ?? '0';
  }

  @override
  Widget build(BuildContext context) {
    final events = overview['recentEvents'];
    final recent = events is List ? events.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList() : const <Map<String, dynamic>>[];
    final tiles = [
      ('Campaigns', _count('campaigns', 'total')),
      ('Active campaigns', _count('campaigns', 'active')),
      ('Referrals', _count('referrals', 'total')),
      ('Qualified referrals', _count('referrals', 'qualified')),
      ('Rewards issued', _count('rewards', 'issued')),
      ('Awaiting approval', _count('rewards', 'awaitingApproval')),
      ('Promotional credits issued', _count('rewards', 'promotionalCredits')),
      ('Points issued', _count('rewards', 'points')),
      ('Fixed coupons issued', _count('rewards', 'fixedCoupons')),
      ('Percentage coupons issued', _count('rewards', 'percentageCoupons')),
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final tile in tiles)
              SizedBox(
                width: 180,
                child: IncentiveCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(tile.$2, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: incentiveGreen)),
                      const SizedBox(height: 4),
                      Text(tile.$1, style: const TextStyle(color: incentiveMuted)),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const Text('Recent activity', style: TextStyle(fontWeight: FontWeight.w800, color: incentiveInk)),
        const SizedBox(height: 8),
        if (recent.isEmpty)
          const IncentiveNotice(message: 'No incentive events yet.')
        else
          for (final event in recent)
            IncentiveCard(
              child: Text(
                '${event['type'] ?? 'Event'} · ${event['status'] ?? ''} · ${incentiveWhen(event['occurredAt'])}',
                style: const TextStyle(color: incentiveInk),
              ),
            ),
        const SizedBox(height: 8),
        const Text(
          'Counts come from the overview route. Reward types come from the campaign version that issued each reward.',
          style: TextStyle(color: incentiveMuted, fontSize: 12),
        ),
      ],
    );
  }
}

class _Campaigns extends StatefulWidget {
  const _Campaigns({
    required this.campaigns,
    required this.isSuperAdmin,
    required this.busy,
    required this.api,
    required this.onChanged,
  });

  final List<Map<String, dynamic>> campaigns;
  final bool isSuperAdmin;
  final bool busy;
  final IncentiveApi api;
  final Future<void> Function() onChanged;

  @override
  State<_Campaigns> createState() => _CampaignsState();
}

class _CampaignsState extends State<_Campaigns> {
  String _query = '';
  String _status = '';

  Future<String?> _askName(BuildContext context, String current) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Duplicate campaign'),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(labelText: 'New name', hintText: current),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Copy')),
        ],
      ),
    );
    controller.dispose();
    return name;
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.campaigns.where((row) {
      final name = '${row['name'] ?? ''} ${row['category'] ?? ''}'.toLowerCase();
      final matchesQuery = _query.isEmpty || name.contains(_query.toLowerCase());
      final matchesStatus = _status.isEmpty || row['status'] == _status;
      return matchesQuery && matchesStatus;
    }).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(labelText: 'Search campaigns', isDense: true),
                  onChanged: (value) => setState(() => _query = value.trim()),
                ),
              ),
              const SizedBox(width: 12),
              DropdownButton<String>(
                value: _status,
                items: const [
                  DropdownMenuItem(value: '', child: Text('All')),
                  DropdownMenuItem(value: 'DRAFT', child: Text('Draft')),
                  DropdownMenuItem(value: 'SCHEDULED', child: Text('Scheduled')),
                  DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                  DropdownMenuItem(value: 'PAUSED', child: Text('Paused')),
                  DropdownMenuItem(value: 'TERMINATED', child: Text('Terminated')),
                ],
                onChanged: (value) => setState(() => _status = value ?? ''),
              ),
            ],
          ),
        ),
        if (widget.isSuperAdmin)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: FilledButton(
                onPressed: widget.busy
                    ? null
                    : () async {
                        final saved = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminCampaignEditor(api: widget.api),
                          ),
                        );
                        if (saved == true) await widget.onChanged();
                      },
                child: const Text('Create campaign'),
              ),
            ),
          ),
        Expanded(
          child: rows.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(20),
                  child: IncentiveNotice(message: 'No campaigns match this search.'),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    return IncentiveCard(
                      child: InkWell(
                        onTap: () async {
                          final saved = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AdminCampaignEditor(
                                api: widget.api,
                                campaignId: row['id']?.toString(),
                                readOnly: !widget.isSuperAdmin,
                              ),
                            ),
                          );
                          if (saved == true) await widget.onChanged();
                        },
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(row['name']?.toString() ?? 'Campaign', style: const TextStyle(fontWeight: FontWeight.w700)),
                            Text('${row['category'] ?? ''} · ${row['status'] ?? ''}'),
                            Wrap(
                              spacing: 4,
                              children: [
                                TextButton(
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => CampaignPerformancePage(
                                          api: widget.api,
                                          campaignId: row['id']?.toString() ?? '',
                                          name: row['name']?.toString() ?? 'Campaign',
                                        ),
                                      ),
                                    );
                                  },
                                  child: const Text('Performance'),
                                ),
                                if (widget.isSuperAdmin)
                                  TextButton(
                                    onPressed: widget.busy
                                        ? null
                                        : () async {
                                            final name = await _askName(context, row['name']?.toString() ?? '');
                                            if (name == null || name.isEmpty) return;
                                            try {
                                              await widget.api.duplicateCampaign(row['id'].toString(), name);
                                              await widget.onChanged();
                                            } on IncentiveException catch (error) {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
                                              }
                                            }
                                          },
                                    child: const Text('Duplicate'),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _Referrals extends StatefulWidget {
  const _Referrals({
    required this.referrals,
    required this.isSuperAdmin,
    required this.busy,
    required this.onDecision,
  });

  final List<Map<String, dynamic>> referrals;
  final bool isSuperAdmin;
  final bool busy;
  final Future<void> Function(String id, String action, String? reason) onDecision;

  @override
  State<_Referrals> createState() => _ReferralsState();
}

class _ReferralsState extends State<_Referrals> {
  String _kind = '';
  String _status = '';

  @override
  Widget build(BuildContext context) {
    final rows = widget.referrals.where((row) {
      final kind = _kind.isEmpty || row['acquisitionKind'] == _kind;
      final status = _status.isEmpty || row['status'] == _status;
      return kind && status;
    }).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: Wrap(
            spacing: 8,
            children: [
              DropdownButton<String>(
                value: _kind,
                items: const [
                  DropdownMenuItem(value: '', child: Text('All types')),
                  DropdownMenuItem(value: 'BUYER_ACQUISITION', child: Text('Buyer')),
                  DropdownMenuItem(value: 'SELLER_ACQUISITION', child: Text('Seller')),
                ],
                onChanged: (value) => setState(() => _kind = value ?? ''),
              ),
              DropdownButton<String>(
                value: _status,
                items: const [
                  DropdownMenuItem(value: '', child: Text('All statuses')),
                  DropdownMenuItem(value: 'ATTRIBUTED', child: Text('Pending')),
                  DropdownMenuItem(value: 'PENDING_REVIEW', child: Text('In review')),
                  DropdownMenuItem(value: 'QUALIFIED', child: Text('Qualified')),
                  DropdownMenuItem(value: 'DISQUALIFIED', child: Text('Rejected')),
                  DropdownMenuItem(value: 'EXPIRED', child: Text('Expired')),
                ],
                onChanged: (value) => setState(() => _status = value ?? ''),
              ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? const Padding(padding: EdgeInsets.all(20), child: IncentiveNotice(message: 'No referrals match this filter.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final row = rows[index];
                    final seller = row['acquisitionKind'] == 'SELLER_ACQUISITION';
                    return IncentiveCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${seller ? 'Seller' : 'Buyer'} referral · ${row['status']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          Text('Referrer ${row['referrerUserId']}'),
                          Text('Referred ${row['referredUserId']}'),
                          Text('Campaign ${row['campaignId'] ?? '—'}'),
                          Text('Attributed ${incentiveWhen(row['attributedAt'])}'),
                          Text(_milestones(row)),
                          if (widget.isSuperAdmin && row['status'] == 'PENDING_REVIEW')
                            Wrap(
                              spacing: 8,
                              children: [
                                TextButton(
                                  onPressed: widget.busy ? null : () => widget.onDecision(row['id'].toString(), 'approve', null),
                                  child: const Text('Qualify'),
                                ),
                                TextButton(
                                  onPressed: widget.busy
                                      ? null
                                      : () async {
                                          final controller = TextEditingController();
                                          final reason = await showDialog<String>(
                                            context: context,
                                            builder: (context) => AlertDialog(
                                              title: const Text('Reject referral'),
                                              content: TextField(
                                                controller: controller,
                                                decoration: const InputDecoration(labelText: 'Reason'),
                                              ),
                                              actions: [
                                                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
                                                FilledButton(
                                                  onPressed: () => Navigator.pop(context, controller.text.trim()),
                                                  child: const Text('Reject'),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (reason == null || reason.isEmpty) return;
                                          await widget.onDecision(row['id'].toString(), 'reject', reason);
                                        },
                                  child: const Text('Reject'),
                                ),
                              ],
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  String _milestones(Map<String, dynamic> row) {
    final seller = row['sellerEnabledAt'] != null ? 'Seller active' : 'Seller pending';
    final listing = row['listingPublishedAt'] != null ? 'Listing done' : 'Listing pending';
    final order = row['qualifyingOrderAt'] != null ? 'Sale done' : 'Sale pending';
    return '$seller · $listing · $order';
  }
}

class _Approvals extends StatelessWidget {
  const _Approvals({
    required this.rewards,
    required this.isSuperAdmin,
    required this.busy,
    required this.onDecision,
  });

  final List<Map<String, dynamic>> rewards;
  final bool isSuperAdmin;
  final bool busy;
  final Future<void> Function(String id, String action, String? reason) onDecision;

  Future<void> _reject(BuildContext context, String id) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reject reward'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Reject')),
        ],
      ),
    );
    if (reason == null || reason.isEmpty) return;
    await onDecision(id, 'reject', reason);
  }

  @override
  Widget build(BuildContext context) {
    if (rewards.isEmpty) {
      return const Padding(padding: EdgeInsets.all(20), child: IncentiveNotice(message: 'No rewards are waiting for approval.'));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(20),
      itemCount: rewards.length,
      itemBuilder: (context, index) {
        final row = rewards[index];
        return IncentiveCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Recipient ${row['recipientUserId']}', style: const TextStyle(fontWeight: FontWeight.w700)),
              Text('${row['amount'] ?? '—'} ${row['currency'] ?? 'INR'} · ${row['rewardSlot'] ?? ''}'),
              Text(incentiveRewardLabel(row['rewardType'])),
              if (!isSuperAdmin)
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text('Only a super admin can approve or reject.', style: TextStyle(color: incentiveMuted)),
                ),
              if (isSuperAdmin)
                Row(
                  children: [
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (context) => AlertDialog(
                                  title: const Text('Approve reward'),
                                  content: const Text('Approval creates the coupon or credit only when issuance is on. If issuance is off, the server refuses.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Approve')),
                                  ],
                                ),
                              );
                              if (ok == true) await onDecision(row['id'].toString(), 'approve', null);
                            },
                      child: const Text('Approve'),
                    ),
                    TextButton(
                      onPressed: busy ? null : () => _reject(context, row['id'].toString()),
                      child: const Text('Reject'),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RewardBoard extends StatelessWidget {
  const _RewardBoard({required this.rewards});

  final List<Map<String, dynamic>> rewards;

  @override
  Widget build(BuildContext context) {
    if (rewards.isEmpty) {
      return const Padding(padding: EdgeInsets.all(20), child: IncentiveNotice(message: 'No incentive rewards have been recorded.'));
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Each row uses the reward type stored on the campaign version.',
          style: TextStyle(color: incentiveMuted, fontSize: 12),
        ),
        const SizedBox(height: 12),
        for (final row in rewards)
          IncentiveCard(
            child: Text(
              '${incentiveRewardLabel(row['rewardType'])} · ${row['status']} · ${row['amount'] ?? '—'} ${row['currency'] ?? ''}\nUser ${row['recipientUserId']}${row['couponId'] == null ? '' : '\nCoupon ${row['couponId']}'}',
            ),
          ),
      ],
    );
  }
}

class _Ledger extends StatefulWidget {
  const _Ledger({required this.api});

  final IncentiveApi api;

  @override
  State<_Ledger> createState() => _LedgerState();
}

class _LedgerState extends State<_Ledger> {
  final _userId = TextEditingController();
  String _entryType = '';
  String _rewardType = '';
  bool _loading = true;
  String? _error;
  String? _cursor;
  List<Map<String, dynamic>> _entries = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _userId.dispose();
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.api.ledger(
        cursor: more ? _cursor : null,
        entryType: _entryType,
        rewardType: _rewardType,
        userId: _userId.text.trim(),
      );
      final rows = page['entries'];
      final next = rows is List ? rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList() : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _entries = more ? [..._entries, ...next] : next;
        _cursor = page['nextCursor']?.toString();
        _loading = false;
      });
    } on IncentiveException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Ledger rows are read-only.', style: TextStyle(color: incentiveMuted)),
        const SizedBox(height: 8),
        TextField(
          controller: _userId,
          decoration: const InputDecoration(labelText: 'User id', isDense: true),
          onSubmitted: (_) => _load(),
        ),
        Wrap(
          spacing: 8,
          children: [
            DropdownButton<String>(
              value: _entryType,
              items: const [
                DropdownMenuItem(value: '', child: Text('All entries')),
                DropdownMenuItem(value: 'ISSUE', child: Text('Issue')),
                DropdownMenuItem(value: 'REDEEM', child: Text('Redeem')),
                DropdownMenuItem(value: 'EXPIRE', child: Text('Expire')),
              ],
              onChanged: (value) {
                setState(() => _entryType = value ?? '');
                _load();
              },
            ),
            DropdownButton<String>(
              value: _rewardType,
              items: const [
                DropdownMenuItem(value: '', child: Text('All reward types')),
                DropdownMenuItem(value: 'FIXED_COUPON', child: Text('Fixed coupon')),
                DropdownMenuItem(value: 'PERCENTAGE_COUPON', child: Text('Percentage coupon')),
                DropdownMenuItem(value: 'PROMOTIONAL_CREDIT', child: Text('Promotional credit')),
                DropdownMenuItem(value: 'POINTS', child: Text('Points')),
              ],
              onChanged: (value) {
                setState(() => _rewardType = value ?? '');
                _load();
              },
            ),
          ],
        ),
        if (_error != null) IncentiveNotice(message: _error!, onRetry: _load),
        if (_loading && _entries.isEmpty) const LinearProgressIndicator(color: incentiveGreen),
        if (!_loading && _entries.isEmpty && _error == null)
          const IncentiveNotice(message: 'No ledger entries match this filter.'),
        for (final entry in _entries)
          IncentiveCard(
            child: Text(
              '${entry['entryType']} ${entry['amount']} · ${incentiveRewardLabel(entry['rewardType'])}\nUser ${entry['recipientUserId']} · ${incentiveWhen(entry['createdAt'])}\n${entry['idempotencyKey']}',
            ),
          ),
        if (_cursor != null && _cursor!.isNotEmpty)
          TextButton(onPressed: _loading ? null : () => _load(more: true), child: const Text('Load more')),
      ],
    );
  }
}

class _Settings extends StatelessWidget {
  const _Settings({
    required this.flags,
    required this.stored,
    required this.busy,
    required this.onToggle,
  });

  final Map<String, bool> flags;
  final Map<String, bool> stored;
  final bool busy;
  final Future<void> Function(String key, String label, bool enabled) onToggle;

  static const _switches = {
    'master': 'Master',
    'referral': 'Referral',
    'buyerReferral': 'Buyer referral',
    'sellerReferral': 'Seller referral',
  };

  static const _readOnly = {
    'issuance': 'Issuance',
    'redemption': 'Redemption',
    'promotional': 'Promotional campaigns',
  };

  String? _inactiveNote(String key) {
    if (stored[key] != true || flags[key] == true) return null;
    if (key == 'referral') return 'Saved, but off until Master is on.';
    if (key == 'buyerReferral' || key == 'sellerReferral') {
      return 'Saved, but off until Master and Referral are on.';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const IncentiveNotice(
          message: 'These switches apply to new referral codes. Turning one off does not delete a code or a reward already stored.',
        ),
        for (final entry in _switches.entries)
          IncentiveCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(entry.value, style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (_inactiveNote(entry.key) != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(_inactiveNote(entry.key)!, style: const TextStyle(color: incentiveMuted, fontSize: 12)),
                        ),
                    ],
                  ),
                ),
                Switch(
                  value: stored[entry.key] == true,
                  activeThumbColor: incentiveGreen,
                  onChanged: busy ? null : (value) => onToggle(entry.key, entry.value, value),
                ),
              ],
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 8, bottom: 8),
          child: Text('Read only', style: TextStyle(color: incentiveMuted, fontWeight: FontWeight.w700)),
        ),
        for (final entry in _readOnly.entries)
          IncentiveCard(
            child: Row(
              children: [
                Expanded(child: Text(entry.value, style: const TextStyle(fontWeight: FontWeight.w700))),
                Text(
                  flags[entry.key] == true ? 'On' : 'Off',
                  style: TextStyle(
                    color: flags[entry.key] == true ? incentiveGreen : incentiveMuted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
