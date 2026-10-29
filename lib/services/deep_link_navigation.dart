import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/data.dart';
import '../screens/buyer_preorder_detail_screen.dart';
import '../screens/food_detail_screen.dart';
import '../screens/login_screen.dart';
import '../screens/seller_storefront_screen.dart';
import 'api_service.dart';
import 'deep_link_service.dart';
import 'session_service.dart';

/// Opens a pending web deep link after the shell is ready.
class DeepLinkNavigation {
  DeepLinkNavigation._();

  static bool _opening = false;

  /// Call from [MainShellScreen] after first frame.
  /// Requires login + society for campaign/seller/listing targets.
  static Future<void> tryOpenPending(BuildContext context) async {
    if (!kIsWeb || _opening || !context.mounted) return;

    final pending = await DeepLinkService.peekPending();
    if (pending == null || !context.mounted) return;

    final signedIn = await _isSignedIn();
    if (!signedIn) {
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      // OTP often replaces the whole stack (this context is disposed). A fresh
      // MainShell will call tryOpenPending again. If login only popped, retry.
      if (!context.mounted) return;
      if (!await _isSignedIn()) return;
      if (!await SessionService.isOnboarded()) return;
      await _consumeAndOpen(context);
      return;
    }

    if (!await SessionService.isOnboarded()) {
      // Society join is still in progress; keep pending for next shell open.
      return;
    }

    await _consumeAndOpen(context);
  }

  static Future<bool> _isSignedIn() async {
    final token = await SessionService.getToken();
    final refresh = await SessionService.getRefreshToken();
    return (token != null && token.isNotEmpty) ||
        (refresh != null && refresh.isNotEmpty);
  }

  static Future<void> _consumeAndOpen(BuildContext context) async {
    if (_opening || !context.mounted) return;
    _opening = true;
    try {
      final target = await DeepLinkService.consumePending();
      if (target == null || !context.mounted) return;
      await _openTarget(context, target);
    } finally {
      _opening = false;
    }
  }

  static Future<void> _openTarget(
    BuildContext context,
    DeepLinkTarget target,
  ) async {
    switch (target.kind) {
      case DeepLinkKind.campaign:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => BuyerPreOrderDetailScreen(campaignId: target.id),
          ),
        );
        return;
      case DeepLinkKind.seller:
        final seller = _placeholderSeller(target.id);
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SellerStorefrontScreen(seller: seller),
          ),
        );
        return;
      case DeepLinkKind.listing:
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _ListingDeepLinkScreen(listingId: target.id),
          ),
        );
        return;
    }
  }

  static Seller placeholderSeller(String sellerId) =>
      _placeholderSeller(sellerId);

  static Seller _placeholderSeller(String sellerId) {
    final hash = sellerId.hashCode.abs();
    const avatarIcons = [
      Icons.person,
      Icons.restaurant,
      Icons.cake,
      Icons.lunch_dining,
      Icons.bakery_dining,
    ];
    const avatarColors = [
      Color(0xFFE8D5C4),
      Color(0xFFD5E8D4),
      Color(0xFFD4D5E8),
      Color(0xFFE8E4D4),
      Color(0xFFE8D4D8),
    ];
    return Seller(
      id: sellerId,
      name: 'Neighbor',
      block: '',
      rating: 0,
      avatarIcon: avatarIcons[hash % avatarIcons.length],
      avatarColor: avatarColors[hash % avatarColors.length],
    );
  }

  static Future<void> copyLink(
    BuildContext context, {
    required String url,
    required String successMessage,
  }) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(successMessage),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Loads a listing by id, then shows [FoodDetailScreen].
class _ListingDeepLinkScreen extends StatefulWidget {
  const _ListingDeepLinkScreen({required this.listingId});

  final String listingId;

  @override
  State<_ListingDeepLinkScreen> createState() => _ListingDeepLinkScreenState();
}

class _ListingDeepLinkScreenState extends State<_ListingDeepLinkScreen> {
  String? _error;
  FoodItem? _food;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _food = null;
    });
    try {
      final raw = await ApiService.getListing(widget.listingId);
      if (!mounted) return;
      setState(() => _food = FoodItem.fromJson(raw));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'This dish is not available right now.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final food = _food;
    if (food != null) {
      return FoodDetailScreen(
        food: food,
        onSellerTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => SellerStorefrontScreen(
                seller: DeepLinkNavigation.placeholderSeller(food.sellerId),
              ),
            ),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF1A2B28),
        elevation: 0,
        title: const Text('Dish'),
      ),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF3A4644),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _load,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              )
            : const CircularProgressIndicator(color: Color(0xFF0E5A47)),
      ),
    );
  }
}
