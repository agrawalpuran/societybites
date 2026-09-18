import 'package:flutter/material.dart';

import '../config/launch_config.dart';
import '../models/data.dart';
import '../models/guest_kitchen.dart';
import '../services/api_service.dart';
import '../widgets/app_header.dart';
import 'seller_storefront_screen.dart';

class GuestKitchensScreen extends StatefulWidget {
  const GuestKitchensScreen({
    super.key,
    this.categoryHint,
    this.fetchKitchens,
  });

  final String? categoryHint;
  final Future<Map<String, dynamic>> Function()? fetchKitchens;

  @override
  State<GuestKitchensScreen> createState() => GuestKitchensScreenState();
}

class GuestKitchensScreenState extends State<GuestKitchensScreen> {
  GuestKitchensResult? _result;
  bool _loading = true;
  bool _hasSuccessfullyLoaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!_hasSuccessfullyLoaded) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final raw = widget.fetchKitchens != null
          ? await widget.fetchKitchens!()
          : await ApiService.getGuestKitchens();
      final result = GuestKitchensResult.fromJson(raw);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
        _hasSuccessfullyLoaded = true;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      if (!_hasSuccessfullyLoaded) {
        setState(() {
          _error = 'Unable to load kitchens right now.';
          _loading = false;
        });
      }
    }
  }

  List<GuestKitchen> get _kitchens {
    final kitchens = _result?.kitchens ?? const <GuestKitchen>[];
    final hint = widget.categoryHint;
    if (hint == null || hint.isEmpty) return kitchens;
    return kitchens
        .where(
          (kitchen) => kitchen.categories.any(
            (category) => category.toLowerCase() == hint.toLowerCase(),
          ),
        )
        .toList();
  }

  void _openKitchen(GuestKitchen kitchen) {
    final seller = Seller(
      id: kitchen.sellerId,
      name: kitchen.sellerName,
      block: kitchen.societyName,
      rating: 0,
      avatarIcon: Icons.restaurant,
      avatarColor: const Color(0xFFD5E8D4),
    );
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SellerStorefrontScreen(
          seller: seller,
          guestBrowse: true,
          guestSocietyName: kitchen.societyName,
          initialProducts: kitchen.listings.map(FoodItem.fromJson).toList(),
          fetchListings: () async {
            final raw = await ApiService.getGuestKitchenStorefront(
              kitchen.sellerId,
            );
            final listings = raw['listings'];
            if (listings is! List) return <Map<String, dynamic>>[];
            return listings
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList();
          },
          fetchCampaigns: () async => const [],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cityName = _result?.cityName ?? currentServingCity;
    return Scaffold(
      backgroundColor: const Color(0xFFF8F6F1),
      body: SafeArea(
        child: Column(
          children: [
            AppHeader(
              leading: IconButton(
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                color: const Color(0xFF3A4644),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFF0E5A47),
                onRefresh: _load,
                child: _body(cityName),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(String cityName) {
    if (_loading && !_hasSuccessfullyLoaded) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        Text(
          'Kitchens in $cityName',
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w800,
            color: Color(0xFF141A18),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Browse real resident cooks. Sign in only when you are ready to order.',
          style: TextStyle(
            color: Color(0xFF5B6764),
            fontWeight: FontWeight.w500,
            height: 1.4,
          ),
        ),
        if (_error != null && !_hasSuccessfullyLoaded) ...[
          const SizedBox(height: 24),
          Text(
            _error!,
            style: const TextStyle(
              color: Color(0xFFB42318),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ] else if (_kitchens.isEmpty) ...[
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: const Color(0xFFE6EBE9)),
            ),
            child: const Column(
              children: [
                Text(
                  'No kitchens available yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101617),
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Resident cooks in this city will appear here when they share an active regular menu.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF6A7774), height: 1.4),
                ),
              ],
            ),
          ),
        ] else ...[
          const SizedBox(height: 18),
          ..._kitchens.map(_kitchenCard),
        ],
      ],
    );
  }

  Widget _kitchenCard(GuestKitchen kitchen) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE6EBE9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kitchen.sellerName,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
          if (kitchen.societyName.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              kitchen.societyName,
              style: const TextStyle(
                color: Color(0xFF3A4644),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (kitchen.categoryLabel != null) ...[
            const SizedBox(height: 6),
            Text(
              kitchen.categoryLabel!,
              style: const TextStyle(color: Color(0xFF6A7774)),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _openKitchen(kitchen),
              child: const Text(
                'View Kitchen',
                style: TextStyle(
                  color: Color(0xFF0E5A47),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
