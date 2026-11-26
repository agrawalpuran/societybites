import 'package:flutter/material.dart';

import '../../admin/admin_city_scope.dart';
import '../../services/api_service.dart';
import '../../widgets/admin_dashboard_cities_table.dart';
import '../../widgets/admin_growth_panel.dart';
import '../../widgets/admin_loading_panel.dart';
import 'admin_city_reach_screen.dart';
import 'admin_serving_cities_screen.dart';
import 'admin_fssai_screen.dart';
import 'admin_festival_banners_screen.dart';
import 'admin_marketing_push_screen.dart';
import 'admin_payment_splits_screen.dart';

String? _canonicalIndianPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return null;
  var ten = digits;
  if (digits.length == 12 && digits.startsWith('91')) {
    ten = digits.substring(2);
  } else if (digits.length == 11 && digits.startsWith('0')) {
    ten = digits.substring(1);
  } else if (digits.length > 10) {
    ten = digits.substring(digits.length - 10);
  }
  if (ten.length != 10) return null;
  return '+91$ten';
}

List<String> _uniquePhones(Iterable<String> phones) {
  final out = <String>[];
  final seen = <String>{};
  for (final phone in phones) {
    if (seen.add(phone)) out.add(phone);
  }
  return out;
}

String _formatTotalSales(Object? raw) {
  final amount = raw is num ? raw.toDouble() : double.tryParse('$raw') ?? 0;
  if (amount == amount.roundToDouble()) {
    return '₹${amount.toStringAsFixed(0)}';
  }
  return '₹${amount.toStringAsFixed(2)}';
}

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen>
    with AdminCityScopeListener<AdminDashboardScreen> {
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _cityRows = const [];
  Map<String, dynamic>? _cityTotals;
  int _cityPeriodDays = 7;
  double _platformFee = 0;
  double _platformFeeGlobal = 0;
  bool _usesGlobalPlatformFee = true;
  bool _whatsappOrderNotifications = false;
  String _paymentProvider = 'direct_upi';
  String _deliveryProvider = 'seller';
  List<String> _deliveryAllowlist = const [];
  int _minIosBuild = 0;
  int _minAndroidBuild = 0;
  String _iosUpdateUrl = '';
  String _androidUpdateUrl = '';
  bool _isLoading = true;
  bool _showGrowthPanel = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  void _scheduleGrowthPanel() {
    if (_showGrowthPanel) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _showGrowthPanel = true);
    });
  }

  @override
  void onAdminCityScopeChanged() {
    _loadStats(keepCitiesTable: true);
  }

  Future<void> _loadStats({bool keepCitiesTable = false}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final futures = <Future<dynamic>>[
        ApiService.getAdminDashboard(cityKey: adminCityKey),
        ApiService.getAdminSettings(cityKey: adminCityKey),
      ];
      if (!keepCitiesTable) {
        futures.add(ApiService.getAdminDashboardCities());
      }
      final results = await Future.wait(futures);
      if (!mounted) return;
      final settings = results[1] as Map<String, dynamic>;
      final stats = results[0] as Map<String, dynamic>;
      Map<String, dynamic>? citiesPayload;
      if (!keepCitiesTable && results.length > 2) {
        citiesPayload = results[2] as Map<String, dynamic>;
      }

      var cityRows = _cityRows;
      var cityTotals = _cityTotals;
      var periodDays = _cityPeriodDays;
      if (citiesPayload != null) {
        final rawRows = citiesPayload['rows'];
        if (rawRows is List) {
          cityRows = rawRows
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList();
        }
        final totals = citiesPayload['totals'];
        if (totals is Map) {
          cityTotals = Map<String, dynamic>.from(totals);
        }
        periodDays = (citiesPayload['periodDays'] as num?)?.toInt() ?? 7;
      }

      setState(() {
        _stats = stats;
        _cityRows = cityRows;
        _cityTotals = cityTotals;
        _cityPeriodDays = periodDays;
        _platformFee = (settings['platformFee'] as num?)?.toDouble() ?? 0;
        _platformFeeGlobal =
            (settings['platformFeeGlobal'] as num?)?.toDouble() ?? _platformFee;
        _usesGlobalPlatformFee = settings['usesGlobalPlatformFee'] != false;
        _whatsappOrderNotifications =
            settings['whatsappOrderNotifications'] == true;
        _paymentProvider =
            settings['paymentProvider']?.toString() ?? 'direct_upi';
        _applyDeliverySettings(settings);
        _minIosBuild = (settings['minIosBuild'] as num?)?.toInt() ?? 0;
        _minAndroidBuild = (settings['minAndroidBuild'] as num?)?.toInt() ?? 0;
        _iosUpdateUrl = settings['iosUpdateUrl']?.toString() ?? '';
        _androidUpdateUrl = settings['androidUpdateUrl']?.toString() ?? '';
        _isLoading = false;
      });
      _scheduleGrowthPanel();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _editForceUpdate() async {
    final iosBuildController = TextEditingController(text: '$_minIosBuild');
    final androidBuildController =
        TextEditingController(text: '$_minAndroidBuild');
    final iosUrlController = TextEditingController(text: _iosUpdateUrl);
    final androidUrlController = TextEditingController(text: _androidUpdateUrl);

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Force update'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Builds below these numbers are blocked at startup. '
                'Set to 0 to disable. Raise only after the new build is on '
                'TestFlight / Play.',
                style: TextStyle(fontSize: 13, color: Color(0xFF6A7774)),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: iosBuildController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Min iOS build (+N)',
                ),
              ),
              TextField(
                controller: androidBuildController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Min Android build (+N)',
                ),
              ),
              TextField(
                controller: iosUrlController,
                decoration: const InputDecoration(
                  labelText: 'iOS update URL (TestFlight / App Store)',
                ),
              ),
              TextField(
                controller: androidUrlController,
                decoration: const InputDecoration(
                  labelText: 'Android update URL (Play)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final ios = int.tryParse(iosBuildController.text.trim());
              final android = int.tryParse(androidBuildController.text.trim());
              if (ios == null || ios < 0 || android == null || android < 0) {
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (saved != true || !mounted) {
      iosBuildController.dispose();
      androidBuildController.dispose();
      iosUrlController.dispose();
      androidUrlController.dispose();
      return;
    }

    final ios = int.parse(iosBuildController.text.trim());
    final android = int.parse(androidBuildController.text.trim());
    final iosUrl = iosUrlController.text.trim();
    final androidUrl = androidUrlController.text.trim();
    iosBuildController.dispose();
    androidBuildController.dispose();
    iosUrlController.dispose();
    androidUrlController.dispose();

    try {
      final updated = await ApiService.updateAdminForceUpdateSettings(
        minIosBuild: ios,
        minAndroidBuild: android,
        iosUpdateUrl: iosUrl,
        androidUpdateUrl: androidUrl,
      );
      if (!mounted) return;
      setState(() {
        _minIosBuild = (updated['minIosBuild'] as num?)?.toInt() ?? ios;
        _minAndroidBuild =
            (updated['minAndroidBuild'] as num?)?.toInt() ?? android;
        _iosUpdateUrl = updated['iosUpdateUrl']?.toString() ?? iosUrl;
        _androidUpdateUrl =
            updated['androidUpdateUrl']?.toString() ?? androidUrl;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Force update settings saved')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update force settings: $e')),
      );
    }
  }

  void _applyPlatformFeeSettings(Map<String, dynamic> settings) {
    _platformFee = (settings['platformFee'] as num?)?.toDouble() ?? 0;
    _platformFeeGlobal =
        (settings['platformFeeGlobal'] as num?)?.toDouble() ?? _platformFee;
    _usesGlobalPlatformFee = settings['usesGlobalPlatformFee'] != false;
  }

  String get _platformFeeCardSubtitle {
    final amount = '₹${_platformFee.toStringAsFixed(0)} at checkout';
    final cityKey = adminCityKey;
    if (cityKey == null || cityKey.isEmpty) {
      return '$amount · app-wide default';
    }
    if (_usesGlobalPlatformFee) {
      return '$amount · uses global (₹${_platformFeeGlobal.toStringAsFixed(0)})';
    }
    final name = AdminCityScope.maybeOf(context)?.selectedDisplayName ?? cityKey;
    return '$amount · $name override';
  }

  Future<void> _editPlatformFee() async {
    final cityKey = adminCityKey;
    final scope = AdminCityScope.maybeOf(context);
    final cityLabel = scope?.selectedDisplayName ?? cityKey;
    final controller = TextEditingController(
      text: _platformFee.toStringAsFixed(
        _platformFee == _platformFee.roundToDouble() ? 0 : 2,
      ),
    );
    final saved = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(cityKey == null ? 'Platform fee (global)' : 'Platform fee'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (cityKey != null) ...[
              Text(
                'City: $cityLabel. Checkout in this city uses the amount below '
                'unless you revert to the global default '
                '(₹${_platformFeeGlobal.toStringAsFixed(0)}).',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount (₹)',
                hintText: '0',
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          if (cityKey != null && !_usesGlobalPlatformFee)
            TextButton(
              onPressed: () => Navigator.pop(ctx, -1),
              child: const Text('Use global default'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final value = double.tryParse(controller.text.trim());
              if (value == null || value < 0) return;
              Navigator.pop(ctx, value);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (saved == null || !mounted) return;

    try {
      if (saved == -1 && cityKey != null) {
        final updated = await ApiService.useGlobalAdminPlatformFee(cityKey: cityKey);
        if (!mounted) return;
        setState(() => _applyPlatformFeeSettings(updated));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Platform fee for $cityLabel uses global '
              '₹${_platformFeeGlobal.toStringAsFixed(0)}',
            ),
          ),
        );
        return;
      }
      final updated = await ApiService.updateAdminPlatformFee(
        saved,
        cityKey: cityKey,
      );
      if (!mounted) return;
      setState(() => _applyPlatformFeeSettings(updated));
      final label = cityKey == null ? 'Global platform fee' : 'City platform fee';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$label set to ₹${_platformFee.toStringAsFixed(0)}',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update fee: $e')),
      );
    }
  }

  void _applyDeliverySettings(Map<String, dynamic> settings) {
    _deliveryProvider =
        settings['deliveryProvider']?.toString() ?? 'seller';
    final raw = settings['deliveryAllowlist'];
    if (raw is List) {
      _deliveryAllowlist = raw
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toList();
    }
  }

  Future<void> _togglePaymentProvider(bool cashfree) async {
    final previous = _paymentProvider;
    final next = cashfree ? 'cashfree' : 'direct_upi';
    setState(() => _paymentProvider = next);
    try {
      final saved = await ApiService.updateAdminPaymentProvider(next);
      if (!mounted) return;
      setState(() => _paymentProvider = saved);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            saved == 'cashfree'
                ? 'New payments use Cashfree'
                : 'New payments use direct UPI',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _paymentProvider = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update payments: $e')),
      );
    }
  }

  Future<void> _toggleDeliveryProvider(bool prorouting) async {
    final previous = _deliveryProvider;
    final next = prorouting ? 'prorouting' : 'seller';
    setState(() => _deliveryProvider = next);
    try {
      final saved = await ApiService.updateAdminDeliverySettings(
        deliveryProvider: next,
      );
      if (!mounted) return;
      setState(() => _applyDeliverySettings(saved));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _deliveryProvider == 'prorouting'
                ? 'Partner delivery on for allowlisted phones'
                : 'Partner delivery off — sellers deliver as today',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deliveryProvider = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update partner delivery: $e')),
      );
    }
  }

  Future<void> _editDeliveryAllowlist() async {
    final draft = _uniquePhones(
      _deliveryAllowlist
          .map(_canonicalIndianPhone)
          .whereType<String>(),
    );
    final confirmed = await showDialog<List<String>>(
      context: context,
      builder: (ctx) => _DeliveryAllowlistDialog(initialPhones: draft),
    );
    if (confirmed == null || !mounted) return;
    try {
      final saved = await ApiService.updateAdminDeliverySettings(
        deliveryAllowlist: confirmed,
      );
      if (!mounted) return;
      setState(() => _applyDeliverySettings(saved));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _deliveryAllowlist.isEmpty
                ? 'Allowlist cleared — no partner bookings'
                : 'Allowlist saved (${_deliveryAllowlist.length} phone${_deliveryAllowlist.length == 1 ? '' : 's'})',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not update allowlist: ${ApiService.userFacingError(e)}',
          ),
        ),
      );
    }
  }

  Future<void> _toggleWhatsAppOrderNotifications(bool value) async {
    final previous = _whatsappOrderNotifications;
    setState(() => _whatsappOrderNotifications = value);
    try {
      final on = await ApiService.updateAdminWhatsAppOrderNotifications(value);
      if (!mounted) return;
      setState(() => _whatsappOrderNotifications = on);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            on
                ? 'WhatsApp order notifications enabled'
                : 'WhatsApp order notifications disabled',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _whatsappOrderNotifications = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update WhatsApp setting: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AdminLoadingPanel(message: 'Loading overview…');
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF6A7774)),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadStats,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0E5A47),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final stats = _stats!;
    final orderWindowDays =
        (stats['orderWindowDays'] as num?)?.toInt() ?? _cityPeriodDays;
    final recent = stats['ordersRecent'] is Map
        ? Map<String, dynamic>.from(stats['ordersRecent'] as Map)
        : <String, dynamic>{};

    return RefreshIndicator(
      color: const Color(0xFF0E5A47),
      onRefresh: _loadStats,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Platform Overview',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Color(0xFF101617),
              ),
            ),
            const SizedBox(height: 16),
            AdminDashboardCitiesTable(
              rows: _cityRows,
              totals: _cityTotals,
              periodDays: _cityPeriodDays,
              selectedCityKey: adminCityKey,
              onSelectCity: (key) =>
                  AdminCityScope.maybeOf(context)?.selectCity(key),
            ),
            const SizedBox(height: 20),
            _SectionTitle(title: 'FSSAI'),
            const SizedBox(height: 10),
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        backgroundColor: const Color(0xFFF8FAF9),
                        appBar: AppBar(
                          backgroundColor: const Color(0xFF0E5A47),
                          foregroundColor: Colors.white,
                          title: const Text('FSSAI'),
                        ),
                        body: const AdminFssaiScreen(),
                      ),
                    ),
                  );
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFEAEFED)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.badge_outlined,
                        size: 22,
                        color: Color(0xFF0E5A47),
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'FSSAI records',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: Color(0xFF101617),
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'View submitted licence details',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF6A7774),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF8A9491),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _SectionTitle(title: 'SETTINGS'),
            if (adminCityKey != null) ...[
              const SizedBox(height: 6),
              Text(
                'Payment and alerts below are app-wide. Platform fee follows the '
                'selected city when you change it.',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  height: 1.35,
                ),
              ),
            ],
            const SizedBox(height: 10),
            _SettingsPair(
              left: _SettingCard(
                icon: Icons.payments_outlined,
                title: 'Platform fee',
                subtitle: _platformFeeCardSubtitle,
                onTap: _editPlatformFee,
              ),
              right: _SettingCard(
                icon: Icons.chat_outlined,
                title: 'WhatsApp',
                subtitle: _whatsappOrderNotifications
                    ? 'Order alerts on'
                    : 'Order alerts off',
                onTap: () => _toggleWhatsAppOrderNotifications(
                  !_whatsappOrderNotifications,
                ),
                trailing: Switch.adaptive(
                  value: _whatsappOrderNotifications,
                  onChanged: _toggleWhatsAppOrderNotifications,
                ),
              ),
            ),
            const SizedBox(height: 8),
            _SettingsPair(
              left: _SettingCard(
                icon: Icons.account_balance_outlined,
                title: 'Payments',
                subtitle: _paymentProvider == 'cashfree'
                    ? 'Cashfree for new orders'
                    : 'Direct UPI for new orders',
                onTap: () =>
                    _togglePaymentProvider(_paymentProvider != 'cashfree'),
                trailing: Switch.adaptive(
                  value: _paymentProvider == 'cashfree',
                  onChanged: _togglePaymentProvider,
                ),
              ),
              right: _SettingCard(
                icon: Icons.pending_actions_outlined,
                title: 'Seller payouts',
                subtitle: 'Splits still waiting',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminPaymentSplitsScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            _SettingsPair(
              left: _SettingCard(
                icon: Icons.delivery_dining_outlined,
                title: 'Partner delivery',
                subtitle: _deliveryProvider == 'prorouting'
                    ? 'Prorouting for allowlisted phones'
                    : 'Off — seller delivery as today',
                onTap: () =>
                    _toggleDeliveryProvider(_deliveryProvider != 'prorouting'),
                trailing: Switch.adaptive(
                  value: _deliveryProvider == 'prorouting',
                  onChanged: _toggleDeliveryProvider,
                ),
              ),
              right: _SettingCard(
                icon: Icons.phone_android_outlined,
                title: 'Delivery allowlist',
                subtitle: _deliveryAllowlist.isEmpty
                    ? 'Empty — nobody is booked'
                    : '${_deliveryAllowlist.length} phone${_deliveryAllowlist.length == 1 ? '' : 's'}',
                onTap: _editDeliveryAllowlist,
              ),
            ),
            const SizedBox(height: 8),
            _SettingsPair(
              left: _SettingCard(
                icon: Icons.system_update_alt_rounded,
                title: 'Force update',
                subtitle: _minIosBuild <= 0 && _minAndroidBuild <= 0
                    ? 'Off — all builds'
                    : 'iOS ≥ $_minIosBuild · And ≥ $_minAndroidBuild',
                onTap: _editForceUpdate,
              ),
              right: _SettingCard(
                icon: Icons.location_city_outlined,
                title: 'Serving cities',
                subtitle: 'Who can join',
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminServingCitiesScreen(),
                    ),
                  );
                  if (mounted) {
                    await AdminCityScope.maybeOf(context)?.reloadActiveCities();
                    await _loadStats();
                  }
                },
              ),
            ),
            const SizedBox(height: 8),
            _SettingsPair(
              left: _SettingCard(
                icon: Icons.travel_explore_outlined,
                title: 'City reach',
                subtitle: 'Selling radii',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminCityReachScreen(),
                    ),
                  );
                },
              ),
              right: _SettingCard(
                icon: Icons.campaign_outlined,
                title: 'Marketing push',
                subtitle: 'One push per week',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminMarketingPushScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            _SettingsPair(
              left: _SettingCard(
                icon: Icons.celebration_outlined,
                title: 'Festival banners',
                subtitle: 'Home announcement',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AdminFestivalBannersScreen(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 24),
            if (_showGrowthPanel)
              AdminGrowthPanel(
                key: ValueKey(adminCityKey ?? 'all'),
                cityKey: adminCityKey,
              ),
            const SizedBox(height: 24),
            _SectionTitle(title: 'USERS'),
            const SizedBox(height: 10),
            _StatsGrid(cards: [
              _StatCard(
                label: 'Total Users',
                value: '${stats['totalUsers'] ?? 0}',
                icon: Icons.people_rounded,
              ),
              _StatCard(
                label: 'Sellers',
                value: '${stats['totalSellers'] ?? 0}',
                icon: Icons.storefront_rounded,
              ),
              _StatCard(
                label: 'Buyers',
                value: '${stats['totalBuyers'] ?? 0}',
                icon: Icons.person_rounded,
              ),
            ]),
            const SizedBox(height: 24),
            _SectionTitle(title: 'SOCIETIES & LISTINGS'),
            const SizedBox(height: 10),
            _StatsGrid(cards: [
              _StatCard(
                label: 'Societies',
                value: '${stats['totalSocieties'] ?? 0}',
                icon: Icons.apartment_rounded,
              ),
              _StatCard(
                label: 'Active Listings',
                value: '${stats['activeListings'] ?? 0}',
                icon: Icons.fastfood_rounded,
                color: const Color(0xFF2E7D32),
              ),
              _StatCard(
                label: 'Sold Out',
                value: '${stats['soldOutListings'] ?? 0}',
                icon: Icons.remove_shopping_cart_rounded,
                color: const Color(0xFFE65100),
              ),
            ]),
            const SizedBox(height: 24),
            _SectionTitle(title: 'ORDERS — LAST $orderWindowDays DAYS'),
            const SizedBox(height: 10),
            _StatsGrid(cards: [
              _StatCard(
                label: 'Orders placed',
                value: '${recent['orders'] ?? 0}',
                icon: Icons.shopping_bag_rounded,
              ),
              _StatCard(
                label: 'Completed',
                value: '${recent['completed'] ?? 0}',
                icon: Icons.check_circle_rounded,
                color: const Color(0xFF2E7D32),
              ),
              _StatCard(
                label: 'Cancelled',
                value: '${recent['cancelled'] ?? 0}',
                icon: Icons.cancel_rounded,
                color: const Color(0xFFC62828),
              ),
              _StatCard(
                label: 'Still pending',
                value: '${recent['pending'] ?? 0}',
                icon: Icons.hourglass_bottom_rounded,
                color: const Color(0xFFF57C00),
              ),
              _StatCard(
                label: 'Food GMV',
                value: _formatTotalSales(recent['foodGmv']),
                icon: Icons.currency_rupee_rounded,
                color: const Color(0xFF0E5A47),
              ),
            ]),
            const SizedBox(height: 24),
            _SectionTitle(title: 'ORDERS — ALL TIME'),
            const SizedBox(height: 10),
            _StatsGrid(cards: [
              _StatCard(
                label: 'Total placed',
                value: '${stats['totalOrders'] ?? 0}',
                icon: Icons.inventory_2_outlined,
              ),
              _StatCard(
                label: 'Placed today',
                value:
                    '${stats['todayOrders'] ?? stats['ordersToday'] ?? 0}',
                icon: Icons.today_rounded,
                color: const Color(0xFF1565C0),
              ),
              _StatCard(
                label: 'Pending now',
                value: '${stats['pendingOrders'] ?? 0}',
                icon: Icons.hourglass_bottom_rounded,
                color: const Color(0xFFF57C00),
              ),
              _StatCard(
                label: 'Completed (lifetime)',
                value: '${stats['completedOrders'] ?? 0}',
                icon: Icons.check_circle_outline_rounded,
                color: const Color(0xFF2E7D32),
              ),
              _StatCard(
                label: 'Cancelled (lifetime)',
                value: '${stats['cancelledOrders'] ?? 0}',
                icon: Icons.cancel_outlined,
                color: const Color(0xFFC62828),
              ),
              _StatCard(
                label: 'Food GMV (lifetime)',
                value: _formatTotalSales(stats['totalSales']),
                icon: Icons.currency_rupee_rounded,
                color: const Color(0xFF0E5A47),
              ),
            ]),
            const SizedBox(height: 24),
            _SectionTitle(title: 'REVIEWS'),
            const SizedBox(height: 10),
            _StatsGrid(cards: [
              _StatCard(
                label: 'Total Reviews',
                value: '${stats['totalReviews'] ?? 0}',
                icon: Icons.star_rounded,
                color: const Color(0xFFF9A825),
              ),
              _StatCard(
                label: 'Avg Rating',
                value:
                    (stats['avgPlatformRating'] as num? ??
                            stats['avgRating'] as num?)
                        ?.toStringAsFixed(1) ??
                    '—',
                icon: Icons.trending_up_rounded,
                color: const Color(0xFFF9A825),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _SettingsPair extends StatelessWidget {
  const _SettingsPair({required this.left, this.right});

  final Widget left;
  final Widget? right;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 8),
        Expanded(child: right ?? const SizedBox.shrink()),
      ],
    );
  }
}

class _SettingCard extends StatelessWidget {
  const _SettingCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFEAEFED)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0E5A47).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, size: 16, color: const Color(0xFF0E5A47)),
                    ),
                    const Spacer(),
                    if (trailing != null)
                      SizedBox(
                        height: 32,
                        child: FittedBox(
                          fit: BoxFit.contain,
                          child: trailing,
                        ),
                      )
                    else
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: Color(0xFF8A9491),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    height: 1.15,
                    color: Color(0xFF101617),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    height: 1.15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF6A7774),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        letterSpacing: 1.4,
        fontWeight: FontWeight.w700,
        color: Color(0xFF8A9491),
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.cards});
  final List<_StatCard> cards;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossAxisCount = constraints.maxWidth > 600 ? 4 : 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: cards.map((card) {
            final width =
                (constraints.maxWidth - (crossAxisCount - 1) * 12) /
                    crossAxisCount;
            return SizedBox(width: width, child: card);
          }).toList(),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    this.color = const Color(0xFF0E5A47),
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6A7774),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryAllowlistDialog extends StatefulWidget {
  const _DeliveryAllowlistDialog({required this.initialPhones});

  final List<String> initialPhones;

  @override
  State<_DeliveryAllowlistDialog> createState() =>
      _DeliveryAllowlistDialogState();
}

class _DeliveryAllowlistDialogState extends State<_DeliveryAllowlistDialog> {
  late final TextEditingController _addController;
  late List<String> _draft;
  String? _fieldError;

  @override
  void initState() {
    super.initState();
    _addController = TextEditingController();
    _draft = List<String>.from(widget.initialPhones);
  }

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  void _addFromField() {
    final tokens = _addController.text
        .split(RegExp(r'[\n\r,;]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty);
    if (tokens.isEmpty) return;
    final next = List<String>.from(_draft);
    for (final token in tokens) {
      final phone = _canonicalIndianPhone(token);
      if (phone == null) {
        setState(() => _fieldError = 'Use a 10-digit number');
        return;
      }
      if (!next.contains(phone)) next.add(phone);
    }
    setState(() {
      _draft = next;
      _fieldError = null;
      _addController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Partner delivery allowlist'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add the buyer phone and the seller phone. The same number is stored once. Empty list books nobody.',
              ),
              const SizedBox(height: 12),
              if (_draft.isEmpty)
                const Text(
                  'Nobody is listed — partner delivery will not book.',
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final phone in _draft)
                      InputChip(
                        label: Text(phone),
                        onDeleted: () {
                          setState(() {
                            _draft = _draft
                                .where((item) => item != phone)
                                .toList();
                          });
                        },
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _addController,
                autofocus: true,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _addFromField(),
                decoration: InputDecoration(
                  labelText: 'Add phone',
                  hintText: '9876543210',
                  errorText: _fieldError,
                  border: const OutlineInputBorder(),
                  suffixIcon: IconButton(
                    onPressed: _addFromField,
                    icon: const Icon(Icons.add),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_addController.text.trim().isNotEmpty) {
              _addFromField();
              if (_addController.text.trim().isNotEmpty) return;
            }
            Navigator.pop(context, List<String>.from(_draft));
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
