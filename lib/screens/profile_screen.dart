import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/session_service.dart';
import '../widgets/app_header.dart';
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
        final profile = await ApiService.getUser(userId);
        await SessionService.cacheProfileFromApi(profile);
        _name = profile['name'] as String? ?? _name;
        _role = profile['role'] as String? ?? _role;
        _phone = profile['phone'] as String? ?? _phone;
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

  void _showComingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature — coming soon')),
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
                            onTap: () => _showComingSoon('Help Center'),
                          ),
                          _MenuTile(
                            icon: Icons.privacy_tip_outlined,
                            title: 'Privacy Policy',
                            onTap: () => _showComingSoon('Privacy Policy'),
                          ),
                          _MenuTile(
                            icon: Icons.description_outlined,
                            title: 'Terms of Service',
                            onTap: () => _showComingSoon('Terms of Service'),
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
