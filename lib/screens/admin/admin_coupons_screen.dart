import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/coupon.dart';
import '../../services/api_service.dart';
import '../../web/web_page_frame.dart';
import '../../widgets/screen_loading_note.dart';
import 'admin_coupon_seller_payouts_screen.dart';

const _green = Color(0xFF0E5A47);

class AdminCouponsScreen extends StatefulWidget {
  const AdminCouponsScreen({super.key, this.loadCoupons});

  final Future<List<AdminCoupon>> Function()? loadCoupons;

  @override
  State<AdminCouponsScreen> createState() => _AdminCouponsScreenState();
}

class _AdminCouponsScreenState extends State<AdminCouponsScreen>
    with SingleTickerProviderStateMixin {
  static const _filters = [
    'ALL',
    'ACTIVE',
    'PAUSED',
    'DRAFT',
    'EXPIRED',
    'EXHAUSTED',
  ];

  List<AdminCoupon> _coupons = const [];
  String _filter = 'ALL';
  bool _loading = true;
  String? _error;
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final load = widget.loadCoupons ?? ApiService.getAdminCoupons;
      final coupons = await load();
      if (!mounted) return;
      setState(() => _coupons = coupons);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = ApiService.userFacingError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<AdminCoupon> get _visible {
    if (_filter == 'ALL') return _coupons;
    return _coupons.where((coupon) => coupon.status == _filter).toList();
  }

  Future<void> _openEditor({String? couponId}) async {
    final createdId = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminCouponEditorScreen(couponId: couponId),
      ),
    );
    if (!mounted) return;
    await _load();
    if (createdId != null && createdId.isNotEmpty && mounted) {
      await _openEditor(couponId: createdId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            'Coupons',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
        ),
        TabBar(
          controller: _tabs,
          labelColor: _green,
          unselectedLabelColor: const Color(0xFF5C6B66),
          indicatorColor: _green,
          tabs: const [
            Tab(text: 'Campaigns'),
            Tab(text: 'Seller payouts'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _buildCampaignsTab(),
              const AdminCouponSellerPayoutsScreen(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCampaignsTab() {
    final visible = _visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'SocietyEats pays the discount. The seller still receives the full order amount.',
                  style: TextStyle(color: Color(0xFF5C6B66), height: 1.35),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _openEditor(),
                style: FilledButton.styleFrom(backgroundColor: _green),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New coupon'),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final filter in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(filter == 'ALL' ? 'All' : _statusLabel(filter)),
                    selected: _filter == filter,
                    onSelected: (_) => setState(() => _filter = filter),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const ScreenLoadingNote(message: 'Loading coupons…')
              : _error != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_error!, textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            TextButton(onPressed: _load, child: const Text('Try again')),
                          ],
                        ),
                      ),
                    )
                  : visible.isEmpty
                      ? const Center(child: Text('No coupons yet'))
                      : RefreshIndicator(
                          color: _green,
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: visible.length,
                            itemBuilder: (context, index) {
                              final coupon = visible[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                elevation: 0,
                                color: Colors.white,
                                child: ListTile(
                                  title: Text(
                                    '${coupon.code} · ${coupon.discountLabel}',
                                    style: const TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  subtitle: Text(
                                    '${coupon.statusLabel} · ${formatCouponDate(coupon.validFrom)} – ${formatCouponDate(coupon.validUntil)}\n'
                                    '${_usageLine(coupon)}',
                                  ),
                                  isThreeLine: true,
                                  onTap: () => _openEditor(couponId: coupon.id),
                                ),
                              );
                            },
                          ),
                        ),
        ),
      ],
    );
  }
}

String _statusLabel(String status) => switch (status) {
      'DRAFT' => 'Draft',
      'ACTIVE' => 'Active',
      'PAUSED' => 'Paused',
      'EXPIRED' => 'Expired',
      'EXHAUSTED' => 'Exhausted',
      _ => status,
    };

String _usageLine(AdminCoupon coupon) {
  final limit = coupon.totalUsageLimit == null ? 'no cap' : '${coupon.totalUsageLimit}';
  final budget = coupon.campaignBudget == null
      ? 'No budget cap'
      : 'Budget ${formatRupee(coupon.amountUsed)} of ${formatRupee(coupon.campaignBudget!)} used';
  return 'Used ${coupon.totalUsage} / $limit · $budget';
}

class AdminCouponEditorScreen extends StatefulWidget {
  const AdminCouponEditorScreen({super.key, this.couponId});

  final String? couponId;

  @override
  State<AdminCouponEditorScreen> createState() => _AdminCouponEditorScreenState();
}

class _AdminCouponEditorScreenState extends State<AdminCouponEditorScreen> {
  final _code = TextEditingController();
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _discount = TextEditingController();
  final _minimum = TextEditingController(text: '0');
  final _totalLimit = TextEditingController();
  final _buyerLimit = TextEditingController(text: '1');
  final _budget = TextEditingController();
  final _userSearch = TextEditingController();

  AdminCoupon? _coupon;
  DateTime _validFrom = DateTime.now();
  DateTime _validUntil = DateTime.now().add(const Duration(days: 30));
  String _frequency = 'ONCE';
  String _audience = 'ALL';
  String _status = 'DRAFT';
  bool _loading = false;
  bool _saving = false;
  String? _error;
  final Map<String, String> _eligible = {};
  List<Map<String, dynamic>> _userHits = const [];
  bool _searchingUsers = false;

  bool get _editing => widget.couponId != null;
  bool get _locked => _coupon?.hasRedemptions == true;

  @override
  void initState() {
    super.initState();
    if (_editing) _load();
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _description.dispose();
    _discount.dispose();
    _minimum.dispose();
    _totalLimit.dispose();
    _buyerLimit.dispose();
    _budget.dispose();
    _userSearch.dispose();
    super.dispose();
  }

  void _apply(AdminCoupon coupon) {
    _coupon = coupon;
    _code.text = coupon.code;
    _name.text = coupon.name;
    _description.text = coupon.description ?? '';
    _discount.text = _trim(coupon.discountValue);
    _minimum.text = _trim(coupon.minimumOrderValue);
    _totalLimit.text = coupon.totalUsageLimit?.toString() ?? '';
    _buyerLimit.text = coupon.usagePerBuyerLimit?.toString() ?? '';
    _budget.text = coupon.campaignBudget == null ? '' : _trim(coupon.campaignBudget!);
    _validFrom = coupon.validFrom.toLocal();
    _validUntil = coupon.validUntil.toLocal();
    _frequency = coupon.usageFrequency ?? 'CUSTOM';
    _audience = coupon.audienceType;
    _status = coupon.status;
    _eligible
      ..clear()
      ..addEntries(coupon.eligibleUserIds.map((id) => MapEntry(id, id)));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final coupon = await ApiService.getAdminCoupon(widget.couponId!);
      if (!mounted) return;
      setState(() => _apply(coupon));
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = ApiService.userFacingError(error));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickDate({required bool from}) async {
    final initial = from ? _validFrom : _validUntil;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2035),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _validFrom = picked;
      } else {
        _validUntil = picked;
      }
    });
  }

  Map<String, dynamic>? _body() {
    final code = _code.text.trim().toUpperCase();
    final name = _name.text.trim();
    final discount = double.tryParse(_discount.text.trim());
    final minimum = double.tryParse(_minimum.text.trim().isEmpty ? '0' : _minimum.text.trim());
    if (code.isEmpty) return _fail('Enter a coupon code');
    if (name.isEmpty) return _fail('Enter a coupon name');
    if (discount == null || discount <= 0) return _fail('Enter a discount greater than zero');
    if (minimum == null || minimum < 0) return _fail('Enter a valid minimum order');
    final from = DateTime(_validFrom.year, _validFrom.month, _validFrom.day);
    final until = DateTime(_validUntil.year, _validUntil.month, _validUntil.day, 23, 59, 59);
    if (!until.isAfter(from)) return _fail('The end date must be after the start date');

    int? optionalInt(String raw, String label) {
      if (raw.trim().isEmpty) return null;
      final value = int.tryParse(raw.trim());
      if (value == null || value < 1) {
        _fail('$label must be a whole number of at least 1');
        return -1;
      }
      return value;
    }

    final total = optionalInt(_totalLimit.text, 'Total usage');
    if (total == -1) return null;
    final perBuyer = optionalInt(_buyerLimit.text, 'Uses per buyer');
    if (perBuyer == -1) return null;
    double? budget;
    if (_budget.text.trim().isNotEmpty) {
      budget = double.tryParse(_budget.text.trim());
      if (budget == null || budget <= 0) return _fail('Enter a valid campaign budget');
    }

    return {
      if (!_locked) 'code': code,
      'name': name,
      'description': _description.text.trim(),
      if (!_locked) 'discountType': 'FIXED',
      if (!_locked) 'discountValue': discount,
      'minimumOrderValue': minimum,
      'validFrom': from.toUtc().toIso8601String(),
      'validUntil': until.toUtc().toIso8601String(),
      'totalUsageLimit': ?total,
      'usagePerBuyerLimit': ?perBuyer,
      'usageFrequency': _frequency,
      'campaignBudget': ?budget,
      'audienceType': _audience,
      if (!_editing) 'status': _status,
    };
  }

  Map<String, dynamic>? _fail(String message) {
    setState(() => _error = message);
    return null;
  }

  Future<void> _save() async {
    final body = _body();
    if (body == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (_editing) {
        final updated = await ApiService.updateAdminCoupon(widget.couponId!, body);
        if (!mounted) return;
        setState(() => _apply(updated));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Coupon saved')),
        );
        Navigator.pop(context);
      } else {
        final created = await ApiService.createAdminCoupon(body);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${created.code} created')),
        );
        Navigator.pop(
          context,
          _audience == 'SELECTED_USERS' ? created.id : null,
        );
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = ApiService.userFacingError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleStatus(bool activate) async {
    final id = widget.couponId;
    if (id == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = activate
          ? await ApiService.activateAdminCoupon(id)
          : await ApiService.pauseAdminCoupon(id);
      if (!mounted) return;
      setState(() => _apply(updated));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(activate ? 'Coupon activated' : 'Coupon paused')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = ApiService.userFacingError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _searchUsers() async {
    final query = _userSearch.text.trim();
    if (query.length < 2) {
      setState(() => _error = 'Enter at least 2 characters to find a buyer');
      return;
    }
    setState(() {
      _searchingUsers = true;
      _error = null;
    });
    try {
      final users = await ApiService.getAdminUsers(search: query);
      if (!mounted) return;
      setState(() => _userHits = users);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = ApiService.userFacingError(error));
    } finally {
      if (mounted) setState(() => _searchingUsers = false);
    }
  }

  Future<void> _saveEligible() async {
    final id = widget.couponId;
    if (id == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await ApiService.setAdminCouponEligibleUsers(
        id,
        _eligible.keys.toList(),
      );
      if (!mounted) return;
      setState(() => _apply(updated));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Eligible buyers saved')),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = ApiService.userFacingError(error));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return panelOnWeb(
      context,
      Scaffold(
        backgroundColor: const Color(0xFFF8FAF9),
        appBar: AppBar(
          backgroundColor: _green,
          foregroundColor: Colors.white,
          title: Text(_editing ? (_coupon?.code ?? 'Coupon') : 'New coupon'),
        ),
        body: _loading
            ? const ScreenLoadingNote(message: 'Loading coupon…')
            : ListView(
                key: const Key('coupon-editor-list'),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_coupon != null) ...[
                    Text(
                      '${_coupon!.statusLabel} · Used ${_coupon!.totalUsage}'
                      '${_coupon!.totalUsageLimit == null ? '' : ' / ${_coupon!.totalUsageLimit}'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(_usageLine(_coupon!)),
                    if (_locked)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          'This coupon has already been used, so the code and discount stay as they are.',
                          style: TextStyle(color: Color(0xFF5C6B66)),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      children: [
                        if (_coupon!.status == 'ACTIVE')
                          OutlinedButton(
                            onPressed: _saving ? null : () => _toggleStatus(false),
                            child: const Text('Pause'),
                          ),
                        if (_coupon!.status == 'PAUSED' || _coupon!.status == 'DRAFT')
                          FilledButton(
                            onPressed: _saving ? null : () => _toggleStatus(true),
                            style: FilledButton.styleFrom(backgroundColor: _green),
                            child: const Text('Activate'),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextField(
                    controller: _code,
                    enabled: !_locked,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Code',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _name,
                    decoration: const InputDecoration(
                      labelText: 'Name',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _description,
                    decoration: const InputDecoration(
                      labelText: 'Description (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _discount,
                    enabled: !_locked,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: const InputDecoration(
                      labelText: 'Fixed discount (₹)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _minimum,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: const InputDecoration(
                      labelText: 'Minimum order (₹)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pickDate(from: true),
                          child: Text('From ${formatCouponDate(_validFrom)}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _pickDate(from: false),
                          child: Text('Until ${formatCouponDate(_validUntil)}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _frequency,
                    decoration: const InputDecoration(
                      labelText: 'How often a buyer can use it',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'ONCE', child: Text('Once')),
                      DropdownMenuItem(value: 'DAILY', child: Text('Once a day')),
                      DropdownMenuItem(value: 'WEEKLY', child: Text('Once a week')),
                      DropdownMenuItem(value: 'MONTHLY', child: Text('Once a month')),
                      DropdownMenuItem(value: 'CUSTOM', child: Text('Custom buyer limit')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _frequency = value);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _buyerLimit,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Uses per buyer',
                      helperText: _editing
                          ? 'Leave blank to keep the current limit'
                          : 'Leave blank for no extra buyer cap',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _totalLimit,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: InputDecoration(
                      labelText: 'Total uses',
                      helperText: _editing
                          ? 'Leave blank to keep the current limit'
                          : 'Leave blank for no total cap',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _budget,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: InputDecoration(
                      labelText: 'Campaign budget (₹)',
                      helperText: _editing
                          ? 'SocietyEats subsidy cap. Leave blank to keep the current budget.'
                          : 'SocietyEats subsidy cap. Leave blank for no cap.',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _audience,
                    decoration: const InputDecoration(
                      labelText: 'Who can use it',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'ALL', child: Text('Everyone')),
                      DropdownMenuItem(value: 'SELECTED_USERS', child: Text('Selected buyers')),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _audience = value);
                    },
                  ),
                  if (!_editing) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _status,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'DRAFT', child: Text('Draft')),
                        DropdownMenuItem(value: 'ACTIVE', child: Text('Active')),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _status = value);
                      },
                    ),
                  ],
                  if (_audience == 'SELECTED_USERS' && !_editing)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text(
                        'Save the coupon first, then choose the buyers who can use it.',
                        style: TextStyle(color: Color(0xFF5C6B66)),
                      ),
                    ),
                  if (_audience == 'SELECTED_USERS' && _editing) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Eligible buyers',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _userSearch,
                            decoration: const InputDecoration(
                              hintText: 'Search name or phone',
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (_) => _searchUsers(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _searchingUsers ? null : _searchUsers,
                          icon: const Icon(Icons.search_rounded),
                          tooltip: 'Search buyers',
                        ),
                      ],
                    ),
                    for (final user in _userHits)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(user['name']?.toString().trim().isNotEmpty == true
                            ? user['name'].toString()
                            : 'Resident'),
                        subtitle: Text(user['phone']?.toString() ?? ''),
                        trailing: TextButton(
                          onPressed: () {
                            final id = user['id']?.toString();
                            if (id == null || id.isEmpty) return;
                            final name = user['name']?.toString().trim();
                            setState(() {
                              _eligible[id] = (name == null || name.isEmpty)
                                  ? (user['phone']?.toString() ?? id)
                                  : name;
                            });
                          },
                          child: const Text('Add'),
                        ),
                      ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final entry in _eligible.entries)
                          InputChip(
                            label: Text(entry.value == entry.key ? 'Saved buyer' : entry.value),
                            onDeleted: () => setState(() => _eligible.remove(entry.key)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _saving ? null : _saveEligible,
                      child: const Text('Save eligible buyers'),
                    ),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Color(0xFFB42318))),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(backgroundColor: _green),
                    child: Text(_saving ? 'Saving…' : 'Save coupon'),
                  ),
                ],
              ),
      ),
    );
  }
}

String _trim(num value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}
