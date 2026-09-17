import 'package:flutter/material.dart';

import '../models/nearby_seller.dart';
import '../services/api_service.dart';
import '../services/seller_onboarding.dart';
import 'seller_storefront_screen.dart';

class ExploreNearbyScreen extends StatefulWidget {
  const ExploreNearbyScreen({
    super.key,
    this.fetchNearby,
    this.onStartSelling,
    this.onOpenStorefront,
  });

  final Future<Map<String, dynamic>> Function()? fetchNearby;
  final VoidCallback? onStartSelling;
  final void Function(NearbySellerCard seller)? onOpenStorefront;

  @override
  State<ExploreNearbyScreen> createState() => ExploreNearbyScreenState();
}

class ExploreNearbyScreenState extends State<ExploreNearbyScreen> {
  NearbyDiscoveryResult? _result;
  bool _loading = true;
  bool _hasSuccessfullyLoaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    final showSpinner = !_hasSuccessfullyLoaded;
    if (showSpinner) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final raw = widget.fetchNearby != null
          ? await widget.fetchNearby!()
          : await ApiService.getNearbySellers();
      final result = NearbyDiscoveryResult.fromJson(raw);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
        _hasSuccessfullyLoaded = true;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      if (!_hasSuccessfullyLoaded) {
        setState(() {
          _error = error.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _startSelling() async {
    if (widget.onStartSelling != null) {
      widget.onStartSelling!();
      return;
    }
    try {
      final enabled = await SellerOnboarding.startSelling(context);
      if (!enabled || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selling enabled — add a listing from Dashboard'),
          backgroundColor: Color(0xFF0E5A47),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not enable selling: $error')),
      );
    }
  }

  void _openStorefront(NearbySellerCard card) {
    if (widget.onOpenStorefront != null) {
      widget.onOpenStorefront!(card);
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SellerStorefrontScreen(
          seller: card.toSeller(),
          nearbyContext: card,
          browseOnly: false,
          initialProducts: card.listings,
          fetchListings: () async {
            final raw = await ApiService.getNearbySellerStorefront(
              card.sellerId,
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
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAF9),
        foregroundColor: const Color(0xFF101617),
        elevation: 0,
        title: const Text(
          'Explore Nearby',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: RefreshIndicator(
        color: const Color(0xFF0E5A47),
        onRefresh: _load,
        child: _body(),
      ),
    );
  }

  Widget _body() {
    if (_loading && !_hasSuccessfullyLoaded) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
      );
    }

    final result = _result;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      children: [
        if (result?.buyerSocietyName != null &&
            result!.buyerSocietyName!.isNotEmpty)
          Text(
            '📍 Near ${result.buyerSocietyName}',
            style: const TextStyle(
              color: Color(0xFF223531),
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
        if (result?.available == true && result?.appliedRadiusKm != null) ...[
          const SizedBox(height: 6),
          Text(
            'Looking up to ${_radiusLabel(result!.appliedRadiusKm!)} km for sellers who opted into Nearby or Extended',
            style: const TextStyle(
              color: Color(0xFF6A7774),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
        if (_error != null && !_hasSuccessfullyLoaded) ...[
          const SizedBox(height: 24),
          Text(
            _error!,
            style: const TextStyle(color: Color(0xFFB42318)),
          ),
        ] else if (result != null &&
            (!result.available || result.sellers.isEmpty)) ...[
          const SizedBox(height: 28),
          _emptyState(result),
        ] else ...[
          const SizedBox(height: 16),
          ...?result?.sellers.map(_sellerCard),
        ],
      ],
    );
  }

  Widget _emptyState(NearbyDiscoveryResult result) {
    final unavailable = !result.available;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE6EBE9)),
      ),
      child: Column(
        children: [
          Text(
            unavailable ? 'Nearby unavailable' : 'No nearby sellers yet',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            unavailable
                ? 'We need your society location to show nearby home cooks.'
                : 'We\'re growing SocietyBites in your area.\nNeighboring cooks appear here only if they choose Nearby selling.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Color(0xFF6A7774),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Want to sell on SocietyBites?',
            style: TextStyle(
              color: Color(0xFF3A4644),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton(
            onPressed: _startSelling,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0E5A47),
            ),
            child: const Text('Start Selling'),
          ),
        ],
      ),
    );
  }

  Widget _sellerCard(NearbySellerCard card) {
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
            card.sellerName,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            card.societyName,
            style: const TextStyle(
              color: Color(0xFF3A4644),
              fontWeight: FontWeight.w600,
            ),
          ),
          if (card.distanceLabel.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              card.distanceLabel,
              style: const TextStyle(color: Color(0xFF6A7774)),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              if (card.offersDelivery)
                _badge('🛵 Seller Delivery'),
              if (card.offersPickup) _badge('🏠 Pickup Available'),
              if (card.deliveryChargeLabel != null)
                _badge(card.deliveryChargeLabel!),
            ],
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _openStorefront(card),
              child: const Text(
                'View Menu',
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

  Widget _badge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF3F7F5),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF223531),
        ),
      ),
    );
  }

  String _radiusLabel(double km) {
    return km == km.roundToDouble() ? km.toInt().toString() : km.toStringAsFixed(1);
  }
}
