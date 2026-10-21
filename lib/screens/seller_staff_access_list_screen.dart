import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../web/web_page_frame.dart';
import '../widgets/app_header.dart';
import '../widgets/status_banner.dart';
import 'seller_dashboard_screen.dart';

/// Owner: kitchens they can oversee (view-only).
class SellerStaffAccessListScreen extends StatefulWidget {
  const SellerStaffAccessListScreen({super.key});

  @override
  State<SellerStaffAccessListScreen> createState() =>
      _SellerStaffAccessListScreenState();
}

class _SellerStaffAccessListScreenState
    extends State<SellerStaffAccessListScreen> {
  List<Map<String, dynamic>> _access = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final access = await ApiService.listSellerStaffAccess();
      if (!mounted) return;
      setState(() {
        _access = access;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  Future<void> _openKitchen(Map<String, dynamic> row) async {
    final sellerId = row['sellerUserId']?.toString() ?? '';
    if (sellerId.isEmpty) return;
    final name = (row['sellerName'] as String?)?.trim();
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SellerDashboardScreen(
          kitchenSellerId: sellerId,
          readOnly: true,
          oversightStoreName: name,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return centerOnWeb(
      context,
      Scaffold(
        backgroundColor: const Color(0xFFF8FAF9),
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppHeader(
                showCart: false,
                padding: const EdgeInsets.fromLTRB(4, 10, 20, 0),
                leading: IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                  color: const Color(0xFF3A4644),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Text(
                  'Stores I oversee',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101617),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 6, 20, 12),
                child: Text(
                  'View-only access to kitchens where you were invited as owner.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6A7774),
                    height: 1.35,
                  ),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(
                          color: Color(0xFF0E5A47),
                        ),
                      )
                    : _error != null
                        ? StatusBanner(
                            message: _error!,
                            action: TextButton(
                              onPressed: _load,
                              child: const Text('Retry'),
                            ),
                          )
                        : RefreshIndicator(
                            color: const Color(0xFF0E5A47),
                            onRefresh: _load,
                            child: ListView(
                              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                              children: [
                                if (_access.isEmpty)
                                  const StatusBanner(
                                    padding: EdgeInsets.zero,
                                    message:
                                        'No store access yet. Ask the store manager to invite your mobile number.',
                                  )
                                else
                                  for (final row in _access)
                                    _AccessTile(
                                      row: row,
                                      onTap: () => _openKitchen(row),
                                    ),
                              ],
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
      maxWidth: 720,
    );
  }
}

class _AccessTile extends StatelessWidget {
  const _AccessTile({required this.row, required this.onTap});

  final Map<String, dynamic> row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = (row['sellerName'] as String?)?.trim();
    final phone = (row['sellerPhone'] as String?)?.trim() ?? '';
    final title = (name != null && name.isNotEmpty) ? name : 'Store';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFEAEFED)),
            ),
            child: Row(
              children: [
                const Icon(Icons.storefront_outlined, color: Color(0xFF0E5A47)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      if (phone.isNotEmpty)
                        Text(
                          phone,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6A7774),
                          ),
                        ),
                      const Text(
                        'View only',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF9A6B00),
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF8A9491),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
