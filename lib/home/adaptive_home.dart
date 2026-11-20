import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/home_screen.dart';
import '../services/api_service.dart';
import '../services/my_listings_cache.dart';
import '../services/my_listings_prefetch.dart';
import '../services/session_service.dart';
import 'chef_hunt_card.dart';
import 'discovery_home.dart';
import 'marketplace_home_state.dart';
import 'marketplace_metrics.dart';

/// Routes Home after the existing screen has loaded its marketplace data.
/// Discovery with no eligible nearby dishes covers [HomeScreen]. When nearby
/// dishes can already be ordered, and when the society already has listings,
/// the existing home stays visible.
class AdaptiveHome extends StatefulWidget {
  const AdaptiveHome({
    super.key,
    required this.homeKey,
    this.onInitialLoadSuccess,
    this.onStartSelling,
    this.onSelectTab,
    this.fetchListings,
    this.fetchNearbySellers,
    this.readProfile,
    this.readOwnListings,
  });

  final GlobalKey<HomeScreenState> homeKey;
  final VoidCallback? onInitialLoadSuccess;
  final VoidCallback? onStartSelling;
  final ValueChanged<int>? onSelectTab;

  /// Test seams. Production leaves these null and uses the existing Home load.
  final Future<List<Map<String, dynamic>>> Function()? fetchListings;
  final Future<Map<String, dynamic>> Function()? fetchNearbySellers;

  /// Test seam for the signed-in profile. Production calls `GET /auth/me`.
  final Future<Map<String, dynamic>> Function()? readProfile;

  /// Test seam for this account's own kitchen. Production uses My Listings.
  final Future<List<Map<String, dynamic>>> Function()? readOwnListings;

  @override
  State<AdaptiveHome> createState() => AdaptiveHomeState();
}

class AdaptiveHomeState extends State<AdaptiveHome> {
  MarketplaceHomeState? _state;
  BuyerMarketplaceSnapshot? _snapshot;
  var _showCookInvite = true;
  var _showChefHunt = false;
  var _chefWing = 'your wing';
  String? _chefSocietyName;
  Future<void>? _inviteRefresh;

  @override
  void initState() {
    super.initState();
    unawaited(refreshSellerInvite());
  }

  /// Hides the cook invite once this seller has listed a product.
  /// A seller with an empty kitchen still sees it. A stored role from an
  /// earlier account is not enough: signup reads the live profile first.
  Future<void> refreshSellerInvite() {
    final active = _inviteRefresh;
    if (active != null) return active;
    final run = _refreshSellerInvite();
    _inviteRefresh = run;
    return run.whenComplete(() {
      if (identical(_inviteRefresh, run)) _inviteRefresh = null;
    });
  }

  Future<void> _refreshSellerInvite() async {
    try {
      final profile = await _signedInProfile();
      final role = profile?.role;
      final selling = role == 'seller' || role == 'super_admin';
      final showHunt = profile != null;
      final wing = chefHuntWingLabel(profile?.block);
      final society = profile?.societyName;
      if (!selling) {
        _applyInvite(
          showCook: true,
          showHunt: showHunt,
          wing: wing,
          society: society,
        );
        return;
      }
      _applyInvite(
        showCook: _showCookInvite,
        showHunt: showHunt,
        wing: wing,
        society: society,
      );
      final hideCook = await _sellerHasListedProduct();
      _applyInvite(
        showCook: !hideCook,
        showHunt: showHunt,
        wing: wing,
        society: society,
      );
    } catch (_) {}
  }

  void _applyInvite({
    required bool showCook,
    required bool showHunt,
    required String wing,
    required String? society,
  }) {
    if (!mounted ||
        (_showCookInvite == showCook &&
            _showChefHunt == showHunt &&
            _chefWing == wing &&
            _chefSocietyName == society)) {
      return;
    }
    setState(() {
      _showCookInvite = showCook;
      _showChefHunt = showHunt;
      _chefWing = wing;
      _chefSocietyName = society;
    });
  }

  /// A known kitchen snapshot answers without another listings request.
  /// The first lookup waits until the society feed has painted, so it does
  /// not compete with the request Home is already waiting on.
  Future<bool> _sellerHasListedProduct() async {
    try {
      if (widget.readOwnListings != null) {
        final rows = await widget.readOwnListings!();
        return rows.isNotEmpty;
      }
      if (MyListingsCache.hasSnapshot) {
        return MyListingsCache.listings.isNotEmpty;
      }
      await _waitUntilHomeFeedSettled();
      if (!mounted) return false;
      if (MyListingsCache.hasSnapshot) {
        return MyListingsCache.listings.isNotEmpty;
      }
      await MyListingsPrefetch.warm();
      return MyListingsCache.listings.isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  Future<void> _waitUntilHomeFeedSettled() async {
    for (var attempt = 0; attempt < 80; attempt++) {
      final home = widget.homeKey.currentState;
      if (home != null && !home.isLoadInProgress) return;
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
  }

  Future<_SignedInProfile?> _signedInProfile() async {
    if (!await SessionService.isSignedIn()) return null;
    try {
      final profile = widget.readProfile != null
          ? await widget.readProfile!()
          : await ApiService.getMe();
      await SessionService.cacheProfileFromApi(profile);
      final live = profile['role'] as String?;
      return _SignedInProfile(
        role: (live == null || live.isEmpty) ? 'buyer' : live,
        block: _nestedString(profile['flat'], 'block'),
        societyName: _nestedString(profile['society'], 'name'),
      );
    } catch (_) {
      return _SignedInProfile(role: await SessionService.getRole());
    }
  }

  String? _nestedString(Object? value, String key) {
    if (value is Map) {
      final raw = value[key];
      if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    }
    return null;
  }

  void _onSnapshot(BuyerMarketplaceSnapshot snapshot) {
    final next = resolveMarketplaceState(snapshot.ownSociety);
    final previousNearby = _snapshot?.nearbyListings.map((food) => food.id).join(',');
    final nextNearby = snapshot.nearbyListings.map((food) => food.id).join(',');
    if (next == _state &&
        _snapshot?.ownSociety.activeSellerCount ==
            snapshot.ownSociety.activeSellerCount &&
        _snapshot?.ownSociety.availableListingCount ==
            snapshot.ownSociety.availableListingCount &&
        previousNearby == nextNearby &&
        _snapshot?.neighbourhoodRadiusKm == snapshot.neighbourhoodRadiusKm &&
        _snapshot?.neighbourHasListed == snapshot.neighbourHasListed) {
      return;
    }
    setState(() {
      _state = next;
      _snapshot = snapshot;
    });
    if (next == MarketplaceHomeState.discovery) {
      unawaited(refreshSellerInvite());
    }
  }

  @override
  Widget build(BuildContext context) {
    final home = HomeScreen(
      key: widget.homeKey,
      onInitialLoadSuccess: widget.onInitialLoadSuccess,
      onStartSelling: widget.onStartSelling,
      onSelectTab: widget.onSelectTab,
      onMarketplaceMetrics: _onSnapshot,
      fetchListings: widget.fetchListings,
      fetchNearbySellers: widget.fetchNearbySellers,
      showChefHunt: _showChefHunt,
      chefWing: _chefWing,
      chefSocietyName: _chefSocietyName,
    );
    final state = _state;
    final snapshot = _snapshot;
    if (state != MarketplaceHomeState.discovery ||
        snapshot == null ||
        snapshot.nearbyListings.isNotEmpty) {
      return home;
    }
    final cover = DiscoveryHome(
      nearbyListings: snapshot.nearbyListings,
      neighbourhoodRadiusKm: snapshot.neighbourhoodRadiusKm,
      neighbourHasListed: snapshot.neighbourHasListed,
      showCookInvite: _showCookInvite,
      showChefHunt: _showChefHunt,
      chefWing: _chefWing,
      chefSocietyName: _chefSocietyName,
      onStartSelling: _showCookInvite ? widget.onStartSelling : null,
      onRefresh: () => widget.homeKey.currentState?.refresh(),
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(child: home),
        cover,
      ],
    );
  }
}

class _SignedInProfile {
  const _SignedInProfile({
    required this.role,
    this.block,
    this.societyName,
  });

  final String? role;
  final String? block;
  final String? societyName;
}
