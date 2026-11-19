import 'package:flutter/material.dart';

import '../../services/incentive_api.dart';
import '../incentive/incentive_theme.dart';

class CampaignPerformancePage extends StatelessWidget {
  const CampaignPerformancePage({super.key, required this.api, required this.campaignId, required this.name});

  final IncentiveApi api;
  final String campaignId;
  final String name;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: incentiveCanvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: incentiveInk,
        elevation: 0,
        title: Text('$name performance'),
      ),
      body: _Loader(
        load: () => api.campaignPerformance(campaignId),
        builder: (data) {
          final referrals = data['referrals'] is Map ? Map<String, dynamic>.from(data['referrals'] as Map) : const <String, dynamic>{};
          final rewards = data['rewards'] is Map ? Map<String, dynamic>.from(data['rewards'] as Map) : const <String, dynamic>{};
          final budget = data['budget'] is Map ? Map<String, dynamic>.from(data['budget'] as Map) : const <String, dynamic>{};
          final schedule = data['schedule'] is Map ? Map<String, dynamic>.from(data['schedule'] as Map) : const <String, dynamic>{};
          final remaining = schedule['remaining'] is Map ? Map<String, dynamic>.from(schedule['remaining'] as Map) : const <String, dynamic>{};
          final series = data['series'] is List ? data['series'] as List : const [];
          final timeline = data['timeline'] is List ? data['timeline'] as List : const [];
          final byType = rewards['byType'] is Map ? rewards['byType'] as Map : const {};
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _metric('Attributed', referrals['attributed']),
                  _metric('Qualified', referrals['qualified']),
                  _metric('Conversion', referrals['conversionRate'] == null ? '—' : '${referrals['conversionRate']}%'),
                  _metric('Pending approval', rewards['pendingApproval']),
                  _metric('Rejected', rewards['rejected']),
                  _metric('Expired rewards', rewards['expired']),
                ],
              ),
              const SizedBox(height: 12),
              IncentiveCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Budget ${budget['configured'] ?? '0.00'} configured'),
                    Text('Consumed ${budget['consumed'] ?? '0.00'}, available ${budget['available'] ?? '0.00'}'),
                    Text('Utilisation ${budget['utilisationPercent'] ?? '—'}%'),
                    if (budget['exhausted'] == true)
                      const Text('Budget exhausted', style: TextStyle(color: Color(0xFF8A3B2C), fontWeight: FontWeight.w700)),
                    Text('${budget['note'] ?? ''}', style: const TextStyle(color: incentiveMuted, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              IncentiveCard(
                child: Text(
                  'Status ${schedule['status'] ?? '—'}. Starts ${incentiveWhen(schedule['startsAt'])}. Ends ${incentiveWhen(schedule['endsAt'])}. Remaining ${remaining['hours'] ?? '—'} hours.',
                ),
              ),
              const SizedBox(height: 12),
              const Text('Rewards by type', style: TextStyle(fontWeight: FontWeight.w800)),
              for (final entry in byType.entries)
                IncentiveCard(
                  child: Text('${incentiveRewardLabel(entry.key.toString())}: ${entry.value}'),
                ),
              const Text('Performance over time', style: TextStyle(fontWeight: FontWeight.w800)),
              if (series.isEmpty) const IncentiveNotice(message: 'No activity in this date range.')
              else
                for (final row in series.whereType<Map>())
                  IncentiveCard(
                    child: Text('${row['day']}: attributed ${row['attributed']}, qualified ${row['qualified']}, issued ${row['issued']}'),
                  ),
              const Text('Status timeline', style: TextStyle(fontWeight: FontWeight.w800)),
              if (timeline.isEmpty) const IncentiveNotice(message: 'No campaign history yet.')
              else
                for (final row in timeline.whereType<Map>())
                  IncentiveCard(
                    child: Text('${row['action']} · ${row['actorId'] ?? 'system'} · ${incentiveWhen(row['createdAt'])}'),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class ReferralAnalyticsTab extends StatelessWidget {
  const ReferralAnalyticsTab({super.key, required this.api});

  final IncentiveApi api;

  @override
  Widget build(BuildContext context) {
    return _Loader(
      load: () => api.referralAnalytics(),
      builder: (data) {
        final funnel = data['funnel'] is Map ? data['funnel'] as Map : const {};
        final comparison = data['comparison'] is Map ? data['comparison'] as Map : const {};
        final failures = data['failures'] is Map ? data['failures'] as Map : const {};
        final recorded = failures['recorded'] is List ? failures['recorded'] as List : const [];
        final other = failures['other'] is List ? failures['other'] as List : const [];
        final leaders = data['leaders'] is List ? data['leaders'] as List : const [];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final key in const ['codesGenerated', 'codesAttributed', 'eligible', 'pendingQualification', 'qualified', 'rewardsApproved', 'rewardsIssued'])
                  _metric(key, funnel[key]),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Buyer and seller', style: TextStyle(fontWeight: FontWeight.w800)),
            for (final entry in comparison.entries)
              IncentiveCard(child: Text('${entry.key}: ${entry.value}')),
            const Text('Recorded failure reasons', style: TextStyle(fontWeight: FontWeight.w800)),
            for (final row in recorded.whereType<Map>())
              IncentiveCard(child: Text('${row['reason']}: ${row['count']}')),
            for (final row in other.whereType<Map>())
              IncentiveCard(child: Text('Other recorded reason ${row['reason']}: ${row['count']}')),
            Text('${failures['note'] ?? ''}', style: const TextStyle(color: incentiveMuted, fontSize: 12)),
            const SizedBox(height: 8),
            const Text('Leaderboard', style: TextStyle(fontWeight: FontWeight.w800)),
            if (leaders.isEmpty) const IncentiveNotice(message: 'No qualified referrers in this range.')
            else
              for (final row in leaders.whereType<Map>())
                IncentiveCard(child: Text('${row['displayName'] ?? 'Member'} · ${row['qualified']} qualified')),
          ],
        );
      },
    );
  }
}

class RewardReportTab extends StatelessWidget {
  const RewardReportTab({super.key, required this.api});

  final IncentiveApi api;

  @override
  Widget build(BuildContext context) {
    return _Loader(
      load: () => api.rewardReport(),
      builder: (data) {
        final counts = data['counts'] is Map ? data['counts'] as Map : const {};
        final balances = data['balances'] is Map ? data['balances'] as Map : const {};
        final exceptions = data['exceptions'] is Map ? data['exceptions'] as Map : const {};
        final timeline = data['timeline'] is List ? data['timeline'] as List : const [];
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [for (final entry in counts.entries) _metric(entry.key.toString(), entry.value)],
            ),
            const SizedBox(height: 12),
            IncentiveCard(
              child: Text(
                'Promotional credit balance ${balances['promotionalCredit'] ?? '0.00'}. Points balance ${balances['points'] ?? '0.00'}. These are not cash and cannot be withdrawn.',
              ),
            ),
            IncentiveCard(
              child: Text('Exceptions: rejected ${exceptions['rejected'] ?? 0}, budget exhausted ${exceptions['budgetExhausted'] ?? 0}, issued past expiry ${exceptions['issuedPastExpiry'] ?? 0}.'),
            ),
            const Text('Redemption timeline', style: TextStyle(fontWeight: FontWeight.w800)),
            if (timeline.isEmpty) const IncentiveNotice(message: 'No ledger entries in this range.')
            else
              for (final row in timeline.whereType<Map>())
                IncentiveCard(child: Text('${row['entryType']} ${row['amount']} · ${incentiveWhen(row['createdAt'])}')),
          ],
        );
      },
    );
  }
}

class EventMonitorTab extends StatefulWidget {
  const EventMonitorTab({super.key, required this.api, required this.isSuperAdmin});

  final IncentiveApi api;
  final bool isSuperAdmin;

  @override
  State<EventMonitorTab> createState() => _EventMonitorTabState();
}

class _EventMonitorTabState extends State<EventMonitorTab> {
  String _status = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          child: DropdownButton<String>(
            value: _status,
            items: const [
              DropdownMenuItem(value: '', child: Text('All statuses')),
              DropdownMenuItem(value: 'PENDING', child: Text('Pending')),
              DropdownMenuItem(value: 'PROCESSING', child: Text('Processing')),
              DropdownMenuItem(value: 'PROCESSED', child: Text('Processed')),
              DropdownMenuItem(value: 'FAILED', child: Text('Failed')),
              DropdownMenuItem(value: 'DEAD', child: Text('Dead letter')),
              DropdownMenuItem(value: 'SKIPPED', child: Text('Skipped')),
            ],
            onChanged: (value) => setState(() => _status = value ?? ''),
          ),
        ),
        Expanded(
          child: _Loader(
            key: ValueKey(_status),
            load: () => widget.api.eventPage(status: _status),
            builder: (data) {
              final events = data['events'] is List ? data['events'] as List : const [];
              if (events.isEmpty) return const IncentiveNotice(message: 'No events match this filter.');
              return ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  for (final row in events.whereType<Map>())
                    IncentiveCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('${row['type']} · ${row['status']} · attempts ${row['attempts'] ?? 0}'),
                          Text('Created ${incentiveWhen(row['createdAt'])}. Processed ${incentiveWhen(row['processedAt'])}.'),
                          if (row['lastError'] != null) Text('Last error: ${row['lastError']}'),
                          if (widget.isSuperAdmin && (row['status'] == 'FAILED' || row['status'] == 'DEAD' || row['status'] == 'SKIPPED'))
                            TextButton(
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Replay event'),
                                    content: const Text('Replay uses the stored event. It does not create a second reward when the original issuance already succeeded.'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                                      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Replay')),
                                    ],
                                  ),
                                );
                                if (confirmed != true || !context.mounted) return;
                                try {
                                  await widget.api.replayEvent(row['id'].toString());
                                  if (context.mounted) setState(() {});
                                } on IncentiveException catch (error) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
                                }
                              },
                              child: const Text('Replay'),
                            )
                          else if (!widget.isSuperAdmin)
                            const Text('Replay is limited to a super admin.', style: TextStyle(color: incentiveMuted, fontSize: 12)),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class AuditLogTab extends StatelessWidget {
  const AuditLogTab({super.key, required this.api});

  final IncentiveApi api;

  @override
  Widget build(BuildContext context) {
    return _Loader(
      load: () => api.auditLog(),
      builder: (data) {
        final entries = data['entries'] is List ? data['entries'] as List : const [];
        if (entries.isEmpty) return const IncentiveNotice(message: 'No audit entries in this range.');
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            for (final row in entries.whereType<Map>())
              IncentiveCard(
                child: Text('${row['action']} · ${row['actorId'] ?? 'system'} · ${incentiveWhen(row['createdAt'])}\n${row['after'] ?? ''}'),
              ),
          ],
        );
      },
    );
  }
}

class RiskTab extends StatelessWidget {
  const RiskTab({super.key, required this.api});

  final IncentiveApi api;

  @override
  Widget build(BuildContext context) {
    return _Loader(
      load: () => api.riskReport(),
      builder: (data) {
        final indicators = data['indicators'] is List ? data['indicators'] as List : const [];
        final shared = data['sharedAccountPatterns'] is Map ? data['sharedAccountPatterns'] as Map : const {};
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            IncentiveNotice(message: data['note']?.toString() ?? 'Indicators need review. They do not reject a reward.'),
            for (final row in indicators.whereType<Map>())
              IncentiveCard(
                child: Text('${row['code']}: ${row['count']}. Review required: ${row['reviewRequired']}. Automatic action: ${row['automaticAction']}.\n${row['detail'] ?? ''}'),
              ),
            IncentiveCard(child: Text('${shared['reason'] ?? ''}')),
          ],
        );
      },
    );
  }
}

class _Loader extends StatefulWidget {
  const _Loader({super.key, required this.load, required this.builder});

  final Future<Map<String, dynamic>> Function() load;
  final Widget Function(Map<String, dynamic> data) builder;

  @override
  State<_Loader> createState() => _LoaderState();
}

class _LoaderState extends State<_Loader> {
  late Future<Map<String, dynamic>> _future = widget.load();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator(color: incentiveGreen));
        }
        if (snapshot.hasError) {
          final error = snapshot.error;
          final message = error is IncentiveException ? error.message : 'Could not load this report.';
          return IncentiveNotice(message: message, onRetry: () => setState(() => _future = widget.load()));
        }
        return widget.builder(snapshot.data ?? const {});
      },
    );
  }
}

Widget _metric(String label, Object? value) {
  return SizedBox(
    width: 160,
    child: IncentiveCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${value ?? 0}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: incentiveGreen)),
          Text(label, style: const TextStyle(color: incentiveMuted, fontSize: 12)),
        ],
      ),
    ),
  );
}
