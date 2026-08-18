import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/session_service.dart';
import '../services/push_notification_service.dart';
import '../widgets/app_header.dart';
import 'admin/admin_shell_screen.dart';
import 'legal_screen.dart';
import 'login_screen.dart';
import 'orders_screen.dart';
import 'seller_dashboard_screen.dart';
import 'my_listings_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, this.onSelectTab});

  /// Switches the main shell tab instead of pushing a new route.
  final ValueChanged<int>? onSelectTab;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  String? _name;
  String? _phone;
  String? _role;
  String? _societyName;
  String? _flatNumber;
  String? _upiId;
  String? _upiDisplayName;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);

    _phone = await SessionService.getPhone();
    _name = await SessionService.getUserName();
    _role = await SessionService.getRole();
    _societyName = await SessionService.getSocietyName();
    _flatNumber = await SessionService.getFlatNumber();

    final userId = await SessionService.getUserId();
    if (userId != null) {
      try {
        final profile = await ApiService.getMe();
        await SessionService.cacheProfileFromApi(profile);
        _name = profile['name'] as String? ?? _name;
        _role = profile['role'] as String? ?? _role;
        _phone = profile['phone'] as String? ?? _phone;
        _upiId = profile['upiId'] as String? ?? _upiId;
        _upiDisplayName =
            profile['upiDisplayName'] as String? ?? _upiDisplayName;
        final society = profile['society'] as Map<String, dynamic>?;
        final flat = profile['flat'] as Map<String, dynamic>?;
        _societyName = society?['name'] as String? ?? _societyName;
        _flatNumber = flat?['flatNumber'] as String? ?? _flatNumber;
      } catch (_) {}
    }

    if (!mounted) return;
    setState(() => _isLoading = false);
  }

  String get _displayName {
    if (_name != null && _name!.isNotEmpty) return _name!;
    if (_phone != null && _phone!.length >= 4) {
      return 'Member ••••${_phone!.substring(_phone!.length - 4)}';
    }
    return 'SocietyBites Member';
  }

  String get _roleLabel {
    switch (_role) {
      case 'seller':
        return 'Seller';
      case 'buyer':
        return 'Buyer';
      default:
        return 'Resident';
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'You will need to verify your phone number again to sign back in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFD94F4F),
            ),
            child: const Text('Log out'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await PushNotificationService.unregister();
    await SessionService.clear();
    await FirebaseAuth.instance.signOut();

    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  void _openOrders() {
    if (widget.onSelectTab != null) {
      widget.onSelectTab!(1);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const OrdersScreen()),
    );
  }

  void _openSellerDashboard() {
    if (widget.onSelectTab != null) {
      widget.onSelectTab!(2);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SellerDashboardScreen()),
    );
  }

  Future<void> _editProfile() async {
    final nameController = TextEditingController(text: _name ?? '');
    final newName = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Edit Profile',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101617),
                ),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Name',
                  filled: true,
                  fillColor: const Color(0xFFF5F7F6),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: Color(0xFF0E5A47)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () =>
                      Navigator.pop(ctx, nameController.text.trim()),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0E5A47),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Save',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (newName == null || newName.isEmpty || !mounted) return;

    try {
      await ApiService.updateMyProfile(name: newName);
      await SessionService.saveUserName(newName);
      await _loadProfile();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update profile: $e')),
      );
    }
  }

  Future<void> _editUpi({bool afterEnableSelling = false}) async {
    final upiController = TextEditingController(text: _upiId ?? '');
    final nameController =
        TextEditingController(text: _upiDisplayName ?? _name ?? '');
    String? errorText;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                24,
                24,
                24 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    afterEnableSelling
                        ? 'Add UPI to receive payments'
                        : 'UPI for Payments',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF101617),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    afterEnableSelling
                        ? 'Selling is on. Add your UPI ID so buyers can pay you for orders.'
                        : 'Buyers will pay this UPI ID when they order your food.',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF6A7774),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 18),
                  TextField(
                    controller: upiController,
                    autofocus: true,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'UPI ID',
                      hintText: 'yourname@oksbi',
                      errorText: errorText,
                      filled: true,
                      fillColor: const Color(0xFFF5F7F6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF0E5A47)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Display name on UPI (optional)',
                      filled: true,
                      fillColor: const Color(0xFFF5F7F6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFFE0E5E3)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(color: Color(0xFF0E5A47)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        final upi = upiController.text.trim();
                        if (upi.isEmpty || !upi.contains('@')) {
                          setSheetState(() {
                            errorText =
                                'Enter a valid UPI ID (e.g. name@oksbi)';
                          });
                          return;
                        }
                        Navigator.pop(ctx, true);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0E5A47),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Save UPI',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (saved != true || !mounted) {
      upiController.dispose();
      nameController.dispose();
      return;
    }

    final upi = upiController.text.trim();
    final displayName = nameController.text.trim();
    upiController.dispose();
    nameController.dispose();

    try {
      await ApiService.updateMyProfile(
        upiId: upi,
        upiDisplayName: displayName.isEmpty ? null : displayName,
      );
      await _loadProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            afterEnableSelling
                ? 'You can sell now — add a listing from Dashboard'
                : 'UPI ID saved',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save UPI: $e')),
      );
    }
  }

  Future<void> _enableSelling() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Start selling?'),
        content: const Text(
          'You will be able to list homemade food for neighbors in your society. '
          'You will need a UPI ID so buyers can pay you directly.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF0E5A47),
            ),
            child: const Text('Enable selling'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ApiService.updateMyProfile(role: 'seller');
      await _loadProfile();
      if (!mounted) return;

      final needsUpi = _upiId == null || _upiId!.isEmpty;
      if (needsUpi) {
        await _editUpi(afterEnableSelling: true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selling enabled — open Dashboard to add a listing'),
            backgroundColor: Color(0xFF0E5A47),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not enable selling: $e')),
      );
    }
  }

  void _openLegal(String title, String content) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LegalScreen(title: title, content: content),
      ),
    );
  }

  void _showAbout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'SocietyBites',
          style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF0E5A47)),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version 1.0.0', style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF3A4644))),
            SizedBox(height: 12),
            Text(
              'A hyperlocal food marketplace for gated communities.',
              style: TextStyle(color: Color(0xFF6A7774), height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close', style: TextStyle(color: Color(0xFF0E5A47))),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      body: SafeArea(
        child: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
              )
            : RefreshIndicator(
                color: const Color(0xFF0E5A47),
                onRefresh: _loadProfile,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  padding: const EdgeInsets.only(bottom: 32),
                  children: [
                    const AppHeader(),
                    const SizedBox(height: 20),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'My Profile',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF101617),
                            ),
                          ),
                          const SizedBox(height: 20),
                          _ProfileCard(
                            name: _displayName,
                            phone: _phone,
                            role: _roleLabel,
                            societyName: _societyName,
                            flatNumber: _flatNumber,
                          ),
                          const SizedBox(height: 24),
                          const Text(
                            'ACCOUNT',
                            style: TextStyle(
                              fontSize: 12,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF8A9491),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _MenuTile(
                            icon: Icons.edit_rounded,
                            title: 'Edit Profile',
                            subtitle: 'Update your display name',
                            onTap: _editProfile,
                          ),
                          _MenuTile(
                            icon: Icons.account_balance_wallet_rounded,
                            title: 'UPI for Payments',
                            subtitle: (_upiId != null && _upiId!.isNotEmpty)
                                ? _upiId!
                                : 'Add UPI ID so buyers can pay you',
                            onTap: () => _editUpi(),
                          ),
                          if (_role == 'buyer' || _role == null)
                            _MenuTile(
                              icon: Icons.storefront_rounded,
                              title: 'Start Selling',
                              subtitle: 'List food for neighbors in your society',
                              onTap: _enableSelling,
                            ),
                          _MenuTile(
                            icon: Icons.receipt_long_rounded,
                            title: 'My Orders',
                            subtitle: 'Track active and past orders',
                            onTap: _openOrders,
                          ),
                          _MenuTile(
                            icon: Icons.inventory_2_outlined,
                            title: 'My Listings',
                            subtitle: 'Edit or remove your food items',
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const MyListingsScreen(),
                                ),
                              );
                            },
                          ),
                          _MenuTile(
                            icon: Icons.grid_view_rounded,
                            title: 'Seller Dashboard',
                            subtitle: 'List food and manage orders',
                            onTap: _openSellerDashboard,
                          ),
                          if (_role == 'super_admin')
                            _MenuTile(
                              icon: Icons.admin_panel_settings_rounded,
                              title: 'Admin Portal',
                              subtitle: 'Manage platform settings',
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const AdminShellScreen(),
                                  ),
                                );
                              },
                            ),
                          const SizedBox(height: 20),
                          const Text(
                            'SUPPORT',
                            style: TextStyle(
                              fontSize: 12,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF8A9491),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _MenuTile(
                            icon: Icons.help_outline_rounded,
                            title: 'Help Center',
                            subtitle: 'FAQs and community support',
                            onTap: () => _openLegal('Help Center',
                              'SocietyBites Help Center\n\n'
                              'Need help? We\'re here for you.\n\n'
                              'Common Questions:\n'
                              '• How do I place an order? Browse listings on the home screen, add items to your cart, and checkout.\n'
                              '• How do I become a seller? Go to Profile → Start Selling, add your UPI ID, then create a listing from Dashboard.\n'
                              '• How do payments work? Buyers pay via UPI or cash on pickup. Sellers receive payments directly.\n'
                              '• How do I change my society? Society cannot be changed after joining. Contact support for assistance.\n\n'
                              'Still need help?\n'
                              'Email us at support@societybites.in\n'
                              'We typically respond within 24 hours.',
                            ),
                          ),
                          _MenuTile(
                            icon: Icons.privacy_tip_outlined,
                            title: 'Privacy Policy',
                            onTap: () => _openLegal('Privacy Policy',
                              'SocietyBites Privacy Policy\n\n'
                              'Last updated: July 2026\n\n'
                              'SocietyBites collects and processes the following information:\n'
                              '• Phone number (for authentication)\n'
                              '• Name (for identification within your society)\n'
                              '• Flat and block number (for delivery coordination)\n'
                              '• UPI ID (for sellers, to receive payments)\n'
                              '• Order history\n\n'
                              'Your data is:\n'
                              '• Never sold to third parties\n'
                              '• Only shared within your apartment society\n'
                              '• Stored securely on encrypted servers\n'
                              '• Deleted upon request\n\n'
                              'For questions: support@societybites.in',
                            ),
                          ),
                          _MenuTile(
                            icon: Icons.description_outlined,
                            title: 'Terms of Service',
                            onTap: () => _openLegal('Terms of Service',
                              'SocietyBites Terms of Service\n\n'
                              'Last updated: July 2026\n\n'
                              'By using SocietyBites, you agree to:\n'
                              '• Provide accurate information about your residence\n'
                              '• Not misuse the platform for commercial resale\n'
                              '• Maintain food safety and hygiene standards (sellers)\n'
                              '• Complete payments for accepted orders (buyers)\n'
                              '• Not share your account credentials\n\n'
                              'SocietyBites is a community platform. We reserve the right to suspend accounts that violate community guidelines.\n\n'
                              'For disputes: support@societybites.in',
                            ),
                          ),
                          _MenuTile(
                            icon: Icons.info_outline_rounded,
                            title: 'About',
                            subtitle: 'App version and info',
                            onTap: _showAbout,
                          ),
                          const SizedBox(height: 28),
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: OutlinedButton.icon(
                              onPressed: _logout,
                              icon: const Icon(Icons.logout_rounded, size: 20),
                              label: const Text(
                                'Log out',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 16,
                                ),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: const Color(0xFFD94F4F),
                                side: const BorderSide(
                                  color: Color(0xFFE8B4B4),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.name,
    required this.phone,
    required this.role,
    required this.societyName,
    required this.flatNumber,
  });

  final String name;
  final String? phone;
  final String role;
  final String? societyName;
  final String? flatNumber;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: const Color(0xFFE8F5EE),
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0E5A47),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101617),
                  ),
                ),
                const SizedBox(height: 4),
                if (phone != null)
                  Text(
                    phone!,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF6A7774),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _Chip(label: role),
                    if (flatNumber != null) _Chip(label: 'Flat $flatNumber'),
                    if (societyName != null) _Chip(label: societyName!),
                  ],
                ),
                if (societyName != null) ...[
                  const SizedBox(height: 8),
                  const Text(
                    'Society cannot be changed after joining',
                    style: TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8A9491),
                      fontWeight: FontWeight.w500,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5EE),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF0E5A47),
        ),
      ),
    );
  }
}

class _MenuTile extends StatelessWidget {
  const _MenuTile({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: ListTile(
        onTap: onTap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFF0F2F1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: const Color(0xFF0E5A47), size: 22),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            color: Color(0xFF101617),
          ),
        ),
        subtitle: subtitle != null
            ? Text(
                subtitle!,
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF6A7774),
                ),
              )
            : null,
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: Color(0xFFADB5B2),
        ),
      ),
    );
  }
}
