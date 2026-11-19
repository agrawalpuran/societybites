import 'package:flutter/material.dart';

import '../../services/incentive_api.dart';
import '../incentive/incentive_theme.dart';
import 'admin_campaign_config_form.dart';

class AdminCampaignEditor extends StatefulWidget {
  const AdminCampaignEditor({
    super.key,
    required this.api,
    this.campaignId,
    this.readOnly = false,
  });

  final IncentiveApi api;
  final String? campaignId;
  final bool readOnly;

  @override
  State<AdminCampaignEditor> createState() => _AdminCampaignEditorState();
}

class _AdminCampaignEditorState extends State<AdminCampaignEditor> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _priority = TextEditingController(text: '0');
  String _category = 'REPEAT_ORDER';
  String _stacking = 'STACK';
  String _trigger = 'USER_REGISTERED';
  bool _loading = false;
  bool _busy = false;
  String? _error;
  Map<String, dynamic>? _campaign;
  Map<String, dynamic> _snapshot = const {};
  String? _status;

  bool get _editing => widget.campaignId != null;

  @override
  void initState() {
    super.initState();
    if (_editing) _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _priority.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final row = await widget.api.campaign(widget.campaignId!);
      final version = row['version'];
      final snapshot = version is Map ? version['snapshot'] : null;
      final triggers = snapshot is Map && snapshot['triggers'] is List ? snapshot['triggers'] as List : const [];
      final firstTrigger = triggers.whereType<Map>().map((item) => item['eventType']?.toString()).whereType<String>().firstOrNull;
      if (!mounted) return;
      setState(() {
        _campaign = row;
        _snapshot = snapshot is Map ? Map<String, dynamic>.from(snapshot) : <String, dynamic>{};
        _status = row['status']?.toString();
        _name.text = row['name']?.toString() ?? '';
        _description.text = row['description']?.toString() ?? '';
        _priority.text = '${row['priority'] ?? 0}';
        _category = row['category']?.toString() ?? _category;
        _stacking = row['stackingMode']?.toString() ?? _stacking;
        _trigger = firstTrigger ?? _trigger;
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

  Future<void> _saveHeader() async {
    if (_busy || widget.readOnly) return;
    setState(() => _busy = true);
    try {
      final body = {
        'name': _name.text.trim(),
        'category': _category,
        'description': _description.text.trim(),
        'priority': int.tryParse(_priority.text.trim()) ?? 0,
        'stackingMode': _stacking,
      };
      if (_editing) {
        await widget.api.updateCampaign(widget.campaignId!, body);
      } else {
        await widget.api.createCampaign(body);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on IncentiveException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _simulate() async {
    if (widget.campaignId == null || _busy) return;
    setState(() => _busy = true);
    try {
      final result = await widget.api.simulate(widget.campaignId!, {'event.type': _trigger});
      if (!mounted) return;
      final passed = result['passed'] == true;
      final failures = result['failures'];
      final message = passed
          ? 'This sample matches the draft rules. Nothing was issued.'
          : 'No match. ${failures is List && failures.isNotEmpty ? failures.first : ''}';
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Simulation'),
          content: Text(message),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
        ),
      );
    } on IncentiveException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _lifecycle(String action, String title) async {
    if (widget.readOnly || widget.campaignId == null || _busy) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: const Text('The server applies this only when the campaign and the incentive switches allow it. Switches stay off unless an administrator changes them outside this app.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(title)),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await widget.api.lifecycle(widget.campaignId!, action);
      if (!mounted) return;
      Navigator.pop(context, true);
    } on IncentiveException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final published = _status != null && _status != 'DRAFT';
    return Scaffold(
      backgroundColor: incentiveCanvas,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: incentiveInk,
        elevation: 0,
        title: Text(_editing ? 'Campaign' : 'New campaign'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: incentiveGreen))
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                if (_status != null) Text('Status $_status', style: const TextStyle(fontWeight: FontWeight.w700)),
                if (published)
                  const Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 8),
                    child: Text('Saving a published campaign creates a new draft. The published version is left unchanged.'),
                  ),
                if (_error != null) IncentiveNotice(message: _error!),
                TextField(controller: _name, readOnly: widget.readOnly, decoration: const InputDecoration(labelText: 'Name')),
                TextField(controller: _description, readOnly: widget.readOnly, decoration: const InputDecoration(labelText: 'Description')),
                DropdownButtonFormField<String>(
                  key: ValueKey('category-$_category'),
                  initialValue: _category,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: const [
                    DropdownMenuItem(value: 'REPEAT_ORDER', child: Text('Repeat order')),
                    DropdownMenuItem(value: 'REFERRAL', child: Text('Referral')),
                    DropdownMenuItem(value: 'BUYER_ACQUISITION', child: Text('Buyer acquisition')),
                    DropdownMenuItem(value: 'SELLER_ACQUISITION', child: Text('Seller acquisition')),
                    DropdownMenuItem(value: 'PROMOTIONAL', child: Text('Promotional')),
                    DropdownMenuItem(value: 'FESTIVE', child: Text('Festive')),
                    DropdownMenuItem(value: 'LISTING', child: Text('Listing')),
                    DropdownMenuItem(value: 'REVIEW', child: Text('Review')),
                  ],
                  onChanged: widget.readOnly ? null : (value) => setState(() => _category = value ?? _category),
                ),
                TextField(controller: _priority, readOnly: widget.readOnly, decoration: const InputDecoration(labelText: 'Priority')),
                DropdownButtonFormField<String>(
                  key: ValueKey('stacking-$_stacking'),
                  initialValue: _stacking,
                  decoration: const InputDecoration(labelText: 'Stacking'),
                  items: const [
                    DropdownMenuItem(value: 'STACK', child: Text('Stack')),
                    DropdownMenuItem(value: 'EXCLUSIVE', child: Text('Exclusive')),
                    DropdownMenuItem(value: 'FIRST_MATCH', child: Text('First match')),
                  ],
                  onChanged: widget.readOnly ? null : (value) => setState(() => _stacking = value ?? _stacking),
                ),
                const SizedBox(height: 12),
                if (!widget.readOnly)
                  FilledButton(onPressed: _busy ? null : _saveHeader, child: Text(_editing ? 'Save draft header' : 'Create draft')),
                if (_editing) ...[
                  const SizedBox(height: 20),
                  AdminCampaignConfigForm(
                    key: ValueKey('${widget.campaignId}-${_campaign?['updatedAt']}'),
                    api: widget.api,
                    campaignId: widget.campaignId!,
                    category: _category,
                    snapshot: _snapshot,
                    readOnly: widget.readOnly,
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton(onPressed: _busy ? null : _simulate, child: const Text('Simulate')),
                  if (!widget.readOnly && (_status == 'DRAFT' || _status == 'SCHEDULED' || _status == 'PAUSED'))
                    TextButton(
                      onPressed: _busy ? null : () => _lifecycle('activate', _status == 'PAUSED' ? 'Resume' : 'Activate'),
                      child: Text(_status == 'PAUSED' ? 'Resume' : 'Activate'),
                    ),
                  if (!widget.readOnly && (_status == 'ACTIVE' || _status == 'SCHEDULED'))
                    TextButton(onPressed: _busy ? null : () => _lifecycle('pause', 'Pause'), child: const Text('Pause')),
                  if (!widget.readOnly && _status != 'TERMINATED' && _status != 'EXPIRED' && _status != 'COMPLETED')
                    TextButton(onPressed: _busy ? null : () => _lifecycle('terminate', 'Terminate'), child: const Text('Terminate')),
                ],
                if (_campaign != null) ...[
                  const SizedBox(height: 16),
                  Text('Version ${_campaign!['currentVersionId'] ?? '—'}', style: const TextStyle(color: incentiveMuted)),
                ],
              ],
            ),
    );
  }
}
