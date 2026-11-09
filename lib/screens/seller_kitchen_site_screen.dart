import 'dart:async';



import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import '../navigation/kitchen_site_navigation.dart';

import '../models/data.dart';

import '../models/storefront_kitchen.dart';

import '../services/api_service.dart';

import '../services/cart_controller.dart';


import '../widgets/storefront_theme_scope.dart';

import 'kitchen_site_marketplace_shell.dart';

import 'seller_storefront_screen.dart';



/// Branded entry for `{slug}.societyeats.com` or `/kitchen/{slug}`.

class SellerKitchenSiteScreen extends StatefulWidget {

  const SellerKitchenSiteScreen({super.key, required this.slug});



  final String slug;



  @override

  State<SellerKitchenSiteScreen> createState() => _SellerKitchenSiteScreenState();

}



class _SellerKitchenSiteScreenState extends State<SellerKitchenSiteScreen> {

  StorefrontKitchenPayload? _payload;

  bool _loading = true;

  String? _error;



  @override

  void initState() {

    super.initState();

    unawaited(KitchenSiteNavigation.holdKitchenSlug(widget.slug));

    CartController.instance.addListener(_onCartChanged);

    _load();

  }



  @override

  void dispose() {

    CartController.instance.removeListener(_onCartChanged);

    super.dispose();

  }



  void _onCartChanged() {

    if (mounted) setState(() {});

  }



  Future<void> _load() async {

    setState(() {

      _loading = true;

      _error = null;

    });

    try {

      final raw = await ApiService.getPublicKitchenBySlug(widget.slug);

      if (!mounted) return;

      setState(() {

        _payload = StorefrontKitchenPayload.fromJson(raw);

        _loading = false;

      });

    } catch (error) {

      if (!mounted) return;

      setState(() {

        _error = ApiService.userFacingError(error);

        _loading = false;

      });

    }

  }



  Future<List<Map<String, dynamic>>> _fetchListings() async {

    final raw = await ApiService.getPublicKitchenBySlug(widget.slug);

    final listings = raw['listings'];

    if (listings is! List) return const [];

    return listings

        .whereType<Map>()

        .map((item) => Map<String, dynamic>.from(item))

        .toList();

  }



  Seller _sellerFromPayload(StorefrontKitchenPayload payload) {

    final hash = payload.sellerId.hashCode.abs();

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

      id: payload.sellerId,

      name: payload.sellerName,

      block: payload.societyName,

      rating: 0,

      avatarIcon: avatarIcons[hash % avatarIcons.length],

      avatarColor: avatarColors[hash % avatarColors.length],

      profilePhotoUrl: payload.seller['profilePhotoUrl']?.toString(),

    );

  }



  @override

  Widget build(BuildContext context) {

    if (_loading) {

      return const Scaffold(

        body: Center(child: CircularProgressIndicator()),

      );

    }

    if (_error != null) {

      return Scaffold(

        body: Center(

          child: Padding(

            padding: const EdgeInsets.all(24),

            child: Text(_error!, textAlign: TextAlign.center),

          ),

        ),

      );

    }

    final payload = _payload;

    if (payload == null) {

      return const Scaffold(

        body: Center(child: Text('Kitchen not found')),

      );

    }



    if (kIsWeb) {

      return KitchenSiteMarketplaceShell(

        slug: widget.slug,

        payload: payload,

      );

    }



    return _buildLegacyMobileStorefront(payload);

  }



  Widget _buildLegacyMobileStorefront(StorefrontKitchenPayload payload) {

    final accent = payload.branding.accentColor;

    final banner = payload.branding.bannerUrl?.trim();

    final tagline = payload.branding.tagline?.trim();

    final initialProducts =

        payload.listings.map(FoodItem.fromJson).toList(growable: false);



    return StorefrontThemeScope(

      accentHex: accent,

      child: Scaffold(

        backgroundColor: const Color(0xFFF8F6F1),

        appBar: AppBar(

          backgroundColor: Colors.white,

          foregroundColor: const Color(0xFF101617),

          elevation: 0,

          title: Text(payload.sellerName),

        ),

        body: Column(

          crossAxisAlignment: CrossAxisAlignment.stretch,

          children: [

            if (banner != null && banner.isNotEmpty)

              Padding(

                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),

                child: ClipRRect(

                  borderRadius: BorderRadius.circular(16),

                  child: AspectRatio(

                    aspectRatio: 3.2,

                    child: Image.network(

                      banner,

                      fit: BoxFit.cover,

                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),

                    ),

                  ),

                ),

              ),

            if (tagline != null && tagline.isNotEmpty)

              Padding(

                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),

                child: Text(

                  tagline,

                  style: const TextStyle(

                    color: Color(0xFF5C6B66),

                    fontWeight: FontWeight.w600,

                  ),

                ),

              ),

            Expanded(

              child: SellerStorefrontScreen(

                seller: _sellerFromPayload(payload),

                guestBrowse: true,

                guestSocietyName: payload.societyName,

                initialProducts: initialProducts,

                cartItems: CartController.instance.items,

                onCartChanged: CartController.instance.notify,

                fetchListings: _fetchListings,

                fetchCampaigns: () async => const [],

              ),

            ),

          ],

        ),

      ),

    );

  }

}
