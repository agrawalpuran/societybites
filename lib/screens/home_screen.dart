import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/listing_image.dart';
import '../utils/listing_timing_chip.dart';
import '../widgets/listing_compact_card_header.dart';
import '../widgets/listing_portion_caption.dart';
import '../widgets/app_header.dart';
import '../widgets/made_to_order_hint.dart';
import '../widgets/recurring_availability_hint.dart';
import '../models/data.dart';
import '../models/kitchen_hours.dart';
import '../models/guest_kitchen.dart';
import '../models/food_type.dart';
import '../models/listing_categories.dart';
import '../services/api_service.dart';
import '../services/cart_controller.dart';
import '../services/home_feed_cache.dart';
import '../services/session_service.dart';
import '../widgets/content_skeleton.dart';
import '../widgets/pull_refresh_gate.dart';
import '../widgets/preorder_widgets.dart';
import 'buyer_preorder_detail_screen.dart';
import 'buyer_preorders_screen.dart';
import 'food_detail_screen.dart';
import 'explore_nearby_screen.dart';
import 'seller_list_screen.dart';
import 'seller_storefront_screen.dart';
import 'tab_preload.dart';
import '../services/seller_onboarding.dart';
import 'home_listing_filter.dart';
import '../models/selling_reach.dart';
import '../widgets/food_type_selector.dart';
import '../widgets/one_seller_cart.dart';
import '../widgets/listing_purchase_slot.dart';
import '../widgets/floating_cart_bar.dart';
import '../widgets/carousel_page_dots.dart';
import '../widgets/home_distance_chip.dart';
import '../widgets/guest_order_auth.dart';
import '../widgets/status_banner.dart';
import '../widgets/listing_rating_mark.dart';
import '../widgets/listing_type_badge.dart';
import '../widgets/seller_avatar.dart';
import '../widgets/feed_refresh_bar.dart';
import '../utils/listing_image_precache.dart';
import '../web/web_breakpoints.dart';
import '../web/web_marketplace_home.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    this.onInitialLoadSuccess,
    this.fetchListings,
    this.fetchNearbySellers,
    this.onStartSelling,
    this.onExploreNearby,
    this.onSelectTab,
    this.initialCategory,
  });

  /// Fired once after the first successful listings load so MainShell can
  /// start conservative background preload of other tabs.
  final VoidCallback? onInitialLoadSuccess;

  /// Test seam. Production uses [ApiService.getListings].
  final Future<List<Map<String, dynamic>>> Function()? fetchListings;

  /// Test seam. Production uses [ApiService.getNearbySellers] after society listings.
  final Future<Map<String, dynamic>> Function()? fetchNearbySellers;

  final VoidCallback? onStartSelling;
  final VoidCallback? onExploreNearby;
  final ValueChanged<int>? onSelectTab;
  final String? initialCategory;

  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final _pullRefresh = PullRefreshGate();
  List<CartItem> get _cart => CartController.instance.items;
  final TextEditingController _searchController = TextEditingController();

  List<FoodItem> _listings = [];
  List<PreOrderCampaign> _preOrderCampaigns = [];
  String? _viewerUserId;
  bool _preOrdersLoading = true;
  bool _isLoading = true;
  bool _hasSuccessfullyLoaded = false;
  bool _webGuestBrowse = false;
  bool _homeSlow = false;
  Timer? _homeSlowTimer;
  bool _feedRefreshing = false;
  String? _error;
  String _searchQuery = '';
  String? _selectedCategory;
  String? _selectedFoodType;
  bool _didNotifyInitialSuccess = false;
  bool _showAllItems = false;
  String? _buyerSocietyId;
  HomeListingReach? _expandedReach;
  SellingReach _cityReach = const SellingReach();
  BuyerDistanceChoice? _distanceChoice;
  HomeListingType _listingType = HomeListingType.all;
  bool _justAdded = false;
  int _listingsLoadGeneration = 0;
  final _reachSectionKeys = <HomeListingReach, GlobalKey>{
    HomeListingReach.inSociety: GlobalKey(),
    HomeListingReach.nearby: GlobalKey(),
    HomeListingReach.extended: GlobalKey(),
  };

  bool get isLoadInProgress => _isLoading;
  bool get hasSuccessfullyLoaded => _hasSuccessfullyLoaded;

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    debugPreloadLog('HOME INITIAL LOAD');
    _searchController.addListener(_onSearchChanged);
    CartController.instance.addListener(_onCartUpdated);
    CartController.instance.onOrderPlaced = _onCartOrderPlaced;
    unawaited(_bootstrapHome());
    _loadPreOrders();
  }

  Future<void> _bootstrapHome() async {
    await _restoreHomeFeedFromDisk();
    if (!mounted) return;
    await _loadListings();
  }

  Future<void> _restoreHomeFeedFromDisk() async {
    final societyId = await SessionService.getSocietyId();
    if (societyId == null || societyId.isEmpty) return;
    final snapshot = await HomeFeedCache.load(societyId);
    if (snapshot == null || !mounted || _hasSuccessfullyLoaded) return;

    final listings = <FoodItem>[];
    for (final map in snapshot.listingMaps) {
      try {
        listings.add(FoodItem.fromJson(map));
      } catch (_) {}
    }
    if (listings.isEmpty) return;

    setState(() {
      _listings = listings;
      _cityReach = snapshot.cityReach;
      _buyerSocietyId = societyId;
      _webGuestBrowse = false;
      _isLoading = false;
      _hasSuccessfullyLoaded = true;
      _error = null;
    });
    _notifyInitialLoadSuccess();
    _scheduleListingImagePrecache(listings);
  }

  void _scheduleListingImagePrecache(List<FoodItem> listings) {
    if (!mounted || listings.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(precacheHomeListingImages(context, listings));
    });
  }

  Future<void> _persistHomeFeedCache(
    List<Map<String, dynamic>> raw,
    SellingReach cityReach,
  ) async {
    if (widget.fetchListings != null || raw.isEmpty) return;
    final societyId = await SessionService.getSocietyId();
    if (societyId == null || societyId.isEmpty) return;
    await HomeFeedCache.save(
      societyId: societyId,
      listingMaps: raw,
      cityReach: cityReach,
    );
  }

  void _armHomeSlowTimer() {
    _homeSlowTimer?.cancel();
    _homeSlow = false;
    _homeSlowTimer = Timer(loadSlowThreshold, () {
      if (!mounted || !_isLoading) return;
      setState(() => _homeSlow = true);
    });
  }

  void _stopHomeSlowTimer() {
    _homeSlowTimer?.cancel();
    _homeSlow = false;
  }

  /// Called by MainShell on failed first-load retry, app resume, and FCM.
  void refresh() {
    _loadListings();
    _loadPreOrders();
  }

  Future<void> _refreshHome() async {
    await Future.wait([_loadListings(), _loadPreOrders()]);
  }

  Future<void> _loadPreOrders() async {
    try {
      final societyId = await SessionService.getSocietyId();
      if (societyId == null || societyId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _preOrderCampaigns = [];
          _preOrdersLoading = false;
        });
        return;
      }
      final userId = await SessionService.getUserId();
      final raw = await ApiService.getPreOrderCampaigns(societyId: societyId);
      final parsed = <PreOrderCampaign>[];
      for (final item in raw) {
        try {
          parsed.add(PreOrderCampaign.fromJson(item));
        } catch (_) {}
      }
      final campaigns = filterBuyerDiscoverableCampaigns(
        parsed,
        viewerUserId: userId,
      );
      if (!mounted) return;
      setState(() {
        _viewerUserId = userId;
        _buyerSocietyId = societyId;
        _preOrderCampaigns = campaigns;
        _preOrdersLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _preOrdersLoading = false);
    }
  }

  @override
  void dispose() {
    _homeSlowTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    CartController.instance.removeListener(_onCartUpdated);
    if (identical(CartController.instance.onOrderPlaced, _onCartOrderPlaced)) {
      CartController.instance.onOrderPlaced = null;
    }
    super.dispose();
  }

  void _onCartUpdated() {
    if (mounted) setState(() {});
  }

  void _onCartOrderPlaced() {
    if (!mounted) return;
    _loadListings();
    _loadPreOrders();
  }

  void _onSearchChanged() {
    setState(() => _searchQuery = _searchController.text.trim());
  }

  String? get webSelectedFoodType => _selectedFoodType;

  void setWebSearch(String value) {
    if (_searchController.text == value) return;
    _searchController.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void setWebFoodType(String? value) {
    if (!mounted || _selectedFoodType == value) return;
    setState(() => _selectedFoodType = value);
  }

  List<FoodItem> get _filteredListings {
    return applyHomeListingFilters(
      _listings,
      category: _selectedCategory,
      searchQuery: _searchQuery,
      foodType: _selectedFoodType,
      listingType: _listingType,
      buyerSocietyId: _buyerSocietyId,
      excludeFssaiBlockedFromBuyerFeed: true,
      justAdded: _justAdded,
    );
  }

  Future<void> _syncBuyerSocietyId() async {
    try {
      final societyId = await SessionService.getSocietyId();
      if (!mounted) return;
      if (societyId != _buyerSocietyId) {
        setState(() => _buyerSocietyId = societyId);
      }
    } catch (_) {}
  }

  Future<void> _paintListings(
    List<Map<String, dynamic>> raw,
    SellingReach cityReach, {
    required bool endInitialLoad,
  }) async {
    if (!mounted) return;
    final listings = raw.map(FoodItem.fromJson).toList();
    if (endInitialLoad) _stopHomeSlowTimer();
    setState(() {
      _listings = listings;
      _webGuestBrowse = false;
      _cityReach = cityReach;
      if (endInitialLoad) {
        _isLoading = false;
        _hasSuccessfullyLoaded = true;
        _homeSlow = false;
        _error = null;
      }
    });
    if (endInitialLoad) {
      _notifyInitialLoadSuccess();
      await _syncBuyerSocietyId();
    }
    _scheduleListingImagePrecache(listings);
    unawaited(_persistHomeFeedCache(raw, cityReach));
  }

  Future<void> _mergeNearbyIntoListings({
    required int generation,
    required List<Map<String, dynamic>> societyRaw,
    required Future<Map<String, dynamic>> nearbyFuture,
  }) async {
    try {
      final nearbyRaw = await nearbyFuture;
      if (!mounted || generation != _listingsLoadGeneration) return;
      final cityReach = SellingReach.fromAuthMe(nearbyRaw);
      final merged = mergeSocietyAndNearbyListingMaps(
        societyRaw,
        listingMapsFromNearbyPayload(nearbyRaw),
      );
      await _paintListings(merged, cityReach, endInitialLoad: false);
    } catch (_) {
      // Society feed is already visible.
    }
  }

  Future<void> _loadListings() async {
    final showSpinner = !_hasSuccessfullyLoaded;
    final generation = ++_listingsLoadGeneration;
    final trackBackgroundRefresh = !showSpinner;
    if (showSpinner) {
      _armHomeSlowTimer();
      setState(() {
        _isLoading = true;
        _error = null;
        _homeSlow = false;
      });
    } else if (mounted) {
      setState(() => _feedRefreshing = true);
    }

    try {
      List<Map<String, dynamic>> raw;
      SellingReach cityReach = _cityReach;
      final fetchListings = widget.fetchListings;
      final shouldLoadNearby =
          fetchListings == null || widget.fetchNearbySellers != null;

      Future<Map<String, dynamic>>? startNearbyRequest() {
        if (!shouldLoadNearby) return null;
        return widget.fetchNearbySellers != null
            ? widget.fetchNearbySellers!()
            : ApiService.getNearbySellers();
      }

      Future<Map<String, dynamic>>? nearbyFuture;

      if (fetchListings != null) {
        nearbyFuture = startNearbyRequest();
        if (nearbyFuture != null && showSpinner) {
          raw = await fetchListings();
          if (!mounted || generation != _listingsLoadGeneration) return;
          await _paintListings(raw, cityReach, endInitialLoad: true);
          unawaited(
            _mergeNearbyIntoListings(
              generation: generation,
              societyRaw: raw,
              nearbyFuture: nearbyFuture,
            ),
          );
          return;
        }
        if (nearbyFuture != null) {
          final results = await Future.wait<Object>([
            fetchListings(),
            nearbyFuture,
          ]);
          raw = results[0] as List<Map<String, dynamic>>;
          try {
            final nearbyRaw = results[1] as Map<String, dynamic>;
            cityReach = SellingReach.fromAuthMe(nearbyRaw);
            raw = mergeSocietyAndNearbyListingMaps(
              raw,
              listingMapsFromNearbyPayload(nearbyRaw),
            );
          } catch (_) {}
        } else {
          raw = await fetchListings();
        }
      } else {
        final societyId = await SessionService.getSocietyId();
        if (societyId == null || societyId.isEmpty) {
          if (kIsWeb) {
            await _loadGuestMarketplace();
            return;
          }
          if (!mounted) return;
          _stopHomeSlowTimer();
          if (!_hasSuccessfullyLoaded) {
            setState(() {
              _listings = [];
              _error = 'Join your society to see listings.';
              _isLoading = false;
            });
          }
          return;
        }
        final societyListingsFuture = ApiService.getListings(
          societyId: societyId,
          catalogType: 'REGULAR',
          status: 'discoverable',
        );
        nearbyFuture = startNearbyRequest();
        if (nearbyFuture != null && showSpinner) {
          raw = await societyListingsFuture;
          if (!mounted || generation != _listingsLoadGeneration) return;
          await _paintListings(raw, cityReach, endInitialLoad: true);
          unawaited(
            _mergeNearbyIntoListings(
              generation: generation,
              societyRaw: raw,
              nearbyFuture: nearbyFuture,
            ),
          );
          return;
        }
        if (nearbyFuture != null) {
          final results = await Future.wait<Object>([
            societyListingsFuture,
            nearbyFuture,
          ]);
          raw = results[0] as List<Map<String, dynamic>>;
          try {
            final nearbyRaw = results[1] as Map<String, dynamic>;
            cityReach = SellingReach.fromAuthMe(nearbyRaw);
            raw = mergeSocietyAndNearbyListingMaps(
              raw,
              listingMapsFromNearbyPayload(nearbyRaw),
            );
          } catch (_) {
            // Home still works if nearby discovery is unavailable.
          }
        } else {
          raw = await societyListingsFuture;
        }
      }

      if (!mounted || generation != _listingsLoadGeneration) return;
      await _paintListings(raw, cityReach, endInitialLoad: showSpinner);
    } catch (e) {
      if (!mounted || generation != _listingsLoadGeneration) return;
      _stopHomeSlowTimer();
      if (!_hasSuccessfullyLoaded) {
        setState(() {
          _listings = [];
          _error = 'Unable to load sellers right now.';
          _isLoading = false;
          _homeSlow = false;
        });
      }
    } finally {
      if (trackBackgroundRefresh &&
          mounted &&
          generation == _listingsLoadGeneration) {
        setState(() => _feedRefreshing = false);
      }
    }
  }

  void _notifyInitialLoadSuccess() {
    if (_didNotifyInitialSuccess) return;
    _didNotifyInitialSuccess = true;
    final callback = widget.onInitialLoadSuccess;
    if (callback == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback();
    });
  }

  BuyerDistanceChoice get _effectiveDistance =>
      effectiveBuyerDistance(_distanceChoice, _cityReach);

  List<FoodItem> get _distanceFiltered => listingsMatchingBuyerDistance(
    _filteredListings,
    choice: _effectiveDistance,
    buyerSocietyId: _buyerSocietyId,
    nearbyRadiusKm: _cityReach.nearbyRadiusKm,
  );

  List<FoodItem> get _available => _distanceFiltered;

  bool get _isBrowsingUnfiltered =>
      _searchQuery.isEmpty &&
      _selectedCategory == null &&
      _selectedFoodType == null &&
      _distanceChoice == null &&
      _listingType == HomeListingType.all &&
      !_justAdded;

  bool get _shouldPreviewAllItems =>
      !_showAllItems &&
      _isBrowsingUnfiltered &&
      _available.length > homeAllItemsPreviewCount;

  List<FoodItem> get _visibleAvailable {
    if (!_shouldPreviewAllItems) return _available;
    return _available.take(homeAllItemsPreviewCount).toList();
  }

  Future<void> _loadGuestMarketplace() async {
    try {
      final raw = await ApiService.getGuestKitchens();
      final result = GuestKitchensResult.fromJson(raw);
      final listings = <FoodItem>[];
      for (final kitchen in result.kitchens) {
        for (final item in kitchen.listings) {
          try {
            listings.add(FoodItem.fromJson(item));
          } catch (_) {}
        }
      }
      if (!mounted) return;
      _stopHomeSlowTimer();
      setState(() {
        _listings = listings;
        _webGuestBrowse = true;
        _isLoading = false;
        _hasSuccessfullyLoaded = true;
        _homeSlow = false;
        _error = null;
      });
      _notifyInitialLoadSuccess();
    } catch (_) {
      if (!mounted) return;
      _stopHomeSlowTimer();
      if (!_hasSuccessfullyLoaded) {
        setState(() {
          _listings = [];
          _error = 'Unable to load kitchens right now.';
          _isLoading = false;
        });
      }
    }
  }

  Future<bool> _webVisitorNeedsSignIn() async {
    if (!kIsWeb) return false;
    final token = await SessionService.getToken();
    final refresh = await SessionService.getRefreshToken();
    final signedIn =
        (token != null && token.isNotEmpty) ||
        (refresh != null && refresh.isNotEmpty);
    if (signedIn || !mounted) return false;
    await showGuestOrderAuthDialog(context);
    return true;
  }

  Future<void> _addToCart(FoodItem food) async {
    if (food.isKitchenClosed) {
      showKitchenClosedMessage(context);
      return;
    }
    if (!food.canAddToCart) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(food.addToCartBlockedMessage()),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: const Color(0xFFD94F4F),
        ),
      );
      return;
    }

    if (await _webVisitorNeedsSignIn()) return;
    if (!mounted) return;

    final allowed = await confirmCartSellerAllowed(
      context,
      cart: _cart,
      sellerId: food.sellerId,
      sellerName: food.sellerName,
      alsoBlockedBy: CartController.instance.items,
      onViewCart: () => CartController.instance.openCheckout(context),
    );
    if (!allowed || !mounted) return;

    final mixConflict = cartAvailabilityConflict(_cart, food);
    if (mixConflict != null) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mixConflict),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: const Color(0xFFD94F4F),
        ),
      );
      return;
    }

    final currentInCart = _cart
        .where((c) => c.food.id == food.id)
        .fold<int>(0, (sum, c) => sum + c.quantity);
    if (currentInCart >= food.quantity) {
      ScaffoldMessenger.of(context).clearSnackBars();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Only ${food.quantity} available for ${food.name}'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: const Color(0xFFD94F4F),
        ),
      );
      return;
    }
    setState(() {
      final existing = _cart.indexWhere((c) => c.food.id == food.id);
      if (existing != -1) {
        _cart[existing].quantity++;
      } else {
        _cart.add(CartItem(food: food));
      }
    });
    CartController.instance.notify();
    ApiService.prefetchPlatformFee();
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          'Item added',
          textAlign: TextAlign.center,
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        ),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
        width: 120,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
    );
  }

  void _removeFromCart(FoodItem food) {
    setState(() {
      final existing = _cart.indexWhere((c) => c.food.id == food.id);
      if (existing != -1) {
        if (_cart[existing].quantity > 1) {
          _cart[existing].quantity--;
        } else {
          _cart.removeAt(existing);
        }
      }
    });
    CartController.instance.notify();
  }

  int _cartQtyFor(FoodItem food) {
    final idx = _cart.indexWhere((c) => c.food.id == food.id);
    return idx != -1 ? _cart[idx].quantity : 0;
  }

  void _openDetail(FoodItem food) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FoodDetailScreen(
          food: food,
          requireAuthToOrder: _webGuestBrowse,
          onSellerTap: () => _openSeller(sellerFromListing(food)),
        ),
      ),
    );
  }

  void _openSeller(Seller seller, {bool hideUnavailableDishes = false}) {
    final sellerListings = _listings
        .where((food) => food.sellerId == seller.id)
        .toList();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SellerStorefrontScreen(
          seller: seller,
          guestBrowse: _webGuestBrowse,
          cartItems: _cart,
          onCartChanged: () {
            CartController.instance.notify();
            if (mounted) setState(() {});
          },
          foodTypeFilter: _selectedFoodType,
          showOnlyOrderable: hideUnavailableDishes,
          initialProducts: sellerListings.isEmpty ? null : sellerListings,
        ),
      ),
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  Map<String, int> _webCategoryCounts() {
    final base = listingsMatchingBuyerDistance(
      applyHomeListingFilters(
        _listings,
        searchQuery: _searchQuery,
        foodType: _selectedFoodType,
        buyerSocietyId: _buyerSocietyId,
        excludeFssaiBlockedFromBuyerFeed: true,
        justAdded: _justAdded,
      ),
      choice: _effectiveDistance,
      buyerSocietyId: _buyerSocietyId,
      nearbyRadiusKm: _cityReach.nearbyRadiusKm,
    );
    final inCategory = _selectedCategory == null
        ? base
        : base
              .where(
                (food) => listingMatchesHomeCategory(
                  food.listingCategories,
                  selectedCategory: _selectedCategory,
                  legacyCategory: food.category,
                ),
              )
              .toList();
    final counts = <String, int>{};
    for (final category in _homeFilterChips) {
      if (category == homeJustAddedFilter) {
        counts[category] = base.where((food) => food.isNewListing()).length;
      } else if (category == 'Made to Order') {
        counts[category] = inCategory
            .where((food) => food.isMadeToOrder)
            .length;
      } else if (category == 'Pre-order') {
        counts[category] = _preorderResultCount;
      } else {
        counts[category] = base
            .where(
              (food) => listingMatchesHomeCategory(
                food.listingCategories,
                selectedCategory: category,
                legacyCategory: food.category,
              ),
            )
            .length;
      }
    }
    return counts;
  }

  Set<String> get _webActiveFilters => {
    ?_selectedCategory,
    if (_justAdded) homeJustAddedFilter,
    if (_listingType == HomeListingType.madeToOrder) 'Made to Order',
    if (_listingType == HomeListingType.preOrder) 'Pre-order',
  };

  int get _homeDishCount =>
      (_listingType == HomeListingType.preOrder
          ? 0
          : _distanceFiltered.length) +
      (_showPreorderSections ? _preorderResultCount : 0);

  void _selectHomeFilter(String? label) {
    if (label == null) {
      setState(() => _selectedCategory = null);
      return;
    }
    setState(() {
      if (label == homeJustAddedFilter) {
        _justAdded = !_justAdded;
      } else if (label == 'Made to Order') {
        _listingType = _listingType == HomeListingType.madeToOrder
            ? HomeListingType.all
            : HomeListingType.madeToOrder;
      } else if (label == 'Pre-order') {
        _listingType = _listingType == HomeListingType.preOrder
            ? HomeListingType.all
            : HomeListingType.preOrder;
      } else {
        _selectedCategory = _selectedCategory == label ? null : label;
      }
    });
  }

  List<FoodItem> _webRegularFor(HomeListingReach reach) {
    return _listingsForReach(
      reach,
    ).where((food) => !food.isMadeToOrder).toList();
  }

  List<FoodItem> get _webReadyNow {
    return _distanceFiltered.where((food) {
      return !food.isMadeToOrder &&
          !food.isPreOrder &&
          !food.isPreOrderCatalog &&
          food.canAddToCart;
    }).toList();
  }

  List<FoodItem> get _webMadeToOrder {
    return _distanceFiltered.where((food) => food.isMadeToOrder).toList();
  }

  List<FoodItem> _webUnscopedRegular() {
    return _distanceFiltered.where((food) {
      if (food.isMadeToOrder) return false;
      return homeListingReachFor(
            food,
            buyerSocietyId: _buyerSocietyId,
            nearbyRadiusKm: _cityReach.nearbyRadiusKm,
          ) ==
          null;
    }).toList();
  }

  List<FoodItem> _webHeroFoods() {
    final withImages = _distanceFiltered
        .where((food) {
          final url = food.imageUrl?.trim();
          return url != null && url.isNotEmpty && url != 'null';
        })
        .take(2)
        .toList();
    if (withImages.isNotEmpty) return withImages;
    return _distanceFiltered.take(1).toList();
  }

  String? _webNearbySubtitle() {
    final km = _cityReach.nearbyRadiusKm;
    if (km == null) return null;
    return 'Sellers within ~${formatReachRadiusKm(km)} km';
  }

  String? _webExtendedSubtitle() {
    final km = _cityReach.extendedRadiusKm;
    if (km == null) return null;
    return 'From other societies (within ~${formatReachRadiusKm(km)} km)';
  }

  Widget _buildWebMarketplace() {
    return WebMarketplaceHome(
      isInitialLoading: _isLoading && !_hasSuccessfullyLoaded,
      isBackgroundRefreshing: _feedRefreshing,
      isSlow: _homeSlow,
      errorMessage: _error,
      showEmptySociety: _showEmptySocietyState,
      searching: _searchQuery.isNotEmpty,
      searchQuery: _searchQuery,
      selectedCategory: _selectedCategory,
      categories: _homeFilterChips,
      categoryCounts: _webCategoryCounts(),
      heroFoods: _webHeroFoods(),
      allFiltered: _distanceFiltered,
      highlights: _webRegularFor(HomeListingReach.inSociety),
      highlightSellers: _societySellers,
      sellerListings: _listings,
      readyNow: _webReadyNow,
      madeToOrder: _webMadeToOrder,
      nearbyListings: _webRegularFor(HomeListingReach.nearby),
      nearbySellers: _nearbySellers,
      nearbySubtitle: _webNearbySubtitle(),
      extendedListings: _webRegularFor(HomeListingReach.extended),
      extendedSellers: _extendedSellers,
      extendedSubtitle: _webExtendedSubtitle(),
      otherListings: _webUnscopedRegular(),
      inSocietyPreorders: _webCampaignsFor(HomeListingReach.inSociety),
      nearbyPreorders: _webCampaignsFor(HomeListingReach.nearby),
      extendedPreorders: _webCampaignsFor(HomeListingReach.extended),
      preordersLoading: _preOrdersLoading,
      viewerUserId: _viewerUserId,
      expandedReach: _expandedReach,
      cartQtyFor: _cartQtyFor,
      onAdd: _addToCart,
      onRemove: _removeFromCart,
      onOpenFood: _openDetail,
      onOpenSeller: (seller) =>
          _openSeller(seller, hideUnavailableDishes: !seller.hasOrderableItems),
      onOpenCampaign: _openBuyerPreOrderDetail,
      onSeePreorders: _openBuyerPreOrders,
      onCategorySelected: _selectHomeFilter,
      listingType: _listingType,
      distanceReach: _cityReach,
      distanceChoice: _distanceChoice,
      dishCount: _homeDishCount,
      onDistanceSelected: (choice) => setState(() => _distanceChoice = choice),
      onListingTypeSelected: (type) => setState(() => _listingType = type),
      activeFilterLabels: _webActiveFilters,
      onExpandReach: _expandReach,
      onCollapseReach: _collapseReach,
      onRetry: _loadListings,
      onRefresh: _refreshHome,
      onStartSelling: _startSellingFromHome,
      onExploreNearby: _openExploreNearby,
      onSelectTab: (index) => widget.onSelectTab?.call(index),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (useWebMarketplaceLayout(context)) {
      return _buildWebMarketplace();
    }
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      floatingActionButton: const FloatingCartBar(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: SafeArea(
        child: RefreshIndicator(
          color: const Color(0xFF0E5A47),
          onRefresh: () => _pullRefresh.run(_refreshHome),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(
                child: FeedRefreshBar(visible: _feedRefreshing),
              ),
              if (_isLoading && !_hasSuccessfullyLoaded) ...[
                SliverToBoxAdapter(child: _buildSearchBar()),
                if (_searchQuery.isEmpty)
                  SliverToBoxAdapter(child: _buildCategoryChips()),
                const SliverToBoxAdapter(child: HomeFeedSkeleton()),
                if (_homeSlow)
                  SliverToBoxAdapter(
                    child: InlineLoadStatus.slow(
                      id: 'home-feed',
                      onRetry: _loadListings,
                    ),
                  ),
              ] else if (_showEmptySocietyState) ...[
                SliverToBoxAdapter(child: _buildEmptySocietyState()),
              ] else ...[
                if (_error != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF0F0),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: const Color(0xFFE8B4B4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Live data unavailable',
                              style: TextStyle(
                                color: Color(0xFFB42318),
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              style: const TextStyle(
                                color: Color(0xFF7A271A),
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: _loadListings,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Retry'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(child: _buildSearchBar()),
                SliverToBoxAdapter(child: _buildDistanceChip()),
                if (_searchQuery.isEmpty) ...[
                  SliverToBoxAdapter(child: _buildCategoryChips()),
                  SliverToBoxAdapter(child: _buildHomeDiscoverySections()),
                ] else if (_listingType == HomeListingType.preOrder) ...[
                  SliverToBoxAdapter(child: _buildPreorderSearchResults()),
                ],
                if (_listingType == HomeListingType.preOrder) ...[
                  if (_preorderResultCount == 0)
                    SliverToBoxAdapter(child: _buildPreorderEmpty()),
                ] else ...[
                  SliverToBoxAdapter(child: _buildAvailableHeader()),
                  _buildAvailableList(),
                  if (_shouldPreviewAllItems)
                    SliverToBoxAdapter(child: _buildSeeAllItemsButton()),
                ],
                SliverToBoxAdapter(
                  child: SizedBox(height: _cart.isEmpty ? 24 : 88),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDistanceChip() {
    return HomeDistanceChip(
      reach: _cityReach,
      selected: _distanceChoice,
      itemCount: _homeDishCount,
      listingType: _listingType,
      onListingTypeSelected: (type) => setState(() => _listingType = type),
      onSelected: (choice) => setState(() => _distanceChoice = choice),
    );
  }

  bool get _showPreorderSections =>
      _listingType == HomeListingType.all ||
      _listingType == HomeListingType.preOrder;

  int get _preorderResultCount => HomeListingReach.values.fold<int>(
    0,
    (sum, reach) => sum + _mobileCampaignsForReach(reach).length,
  );

  Widget _buildPreorderSearchResults() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildPreOrdersSection(),
        _buildPreOrderReachCarousel(
          title: 'Pre-orders Nearby',
          campaigns: _mobileCampaignsForReach(HomeListingReach.nearby),
        ),
        _buildPreOrderReachCarousel(
          title: 'Pre-orders Around You',
          campaigns: _mobileCampaignsForReach(HomeListingReach.extended),
        ),
      ],
    );
  }

  Widget _buildPreorderEmpty() {
    return StatusBanner(
      message: _searchQuery.isNotEmpty
          ? 'No listings match "$_searchQuery".'
          : _selectedCategory != null
          ? 'No listings in $_selectedCategory yet.'
          : 'No listings yet. Be the first to add food from the seller dashboard.',
    );
  }

  List<FoodItem> _mobileListingsForReach(HomeListingReach reach) {
    return listingsForHomeReach(
      _distanceFiltered,
      reach: reach,
      buyerSocietyId: _buyerSocietyId,
      nearbyRadiusKm: _cityReach.nearbyRadiusKm,
    );
  }

  /// Seller circles include cooks whose dishes are expired or sold out.
  /// Dish rows stay on [_mobileListingsForReach], which keeps those dishes out.
  List<FoodItem> _sellerPresenceForReach(HomeListingReach reach) {
    final presence = applyHomeListingFilters(
      _listings,
      category: _selectedCategory,
      searchQuery: _searchQuery,
      foodType: _selectedFoodType,
      listingType: _listingType,
      buyerSocietyId: _buyerSocietyId,
      includeNotSelling: true,
      justAdded: _justAdded,
    );
    final distanceMatched = listingsMatchingBuyerDistance(
      presence,
      choice: _effectiveDistance,
      buyerSocietyId: _buyerSocietyId,
      nearbyRadiusKm: _cityReach.nearbyRadiusKm,
    );
    return listingsForHomeReach(
      distanceMatched,
      reach: reach,
      buyerSocietyId: _buyerSocietyId,
      nearbyRadiusKm: _cityReach.nearbyRadiusKm,
    );
  }

  List<PreOrderCampaign> _mobileCampaignsForReach(HomeListingReach reach) {
    final distanceMatched = campaignsMatchingBuyerDistance(
      _preOrderCampaigns,
      choice: _effectiveDistance,
      buyerSocietyId: _buyerSocietyId,
      viewerUserId: _viewerUserId,
      nearbyRadiusKm: _cityReach.nearbyRadiusKm,
    );
    final narrow =
        _listingType == HomeListingType.preOrder ||
        _selectedFoodType != null ||
        _searchQuery.isNotEmpty ||
        (_selectedCategory != null && _selectedCategory != 'All');
    final visible = narrow
        ? campaignsMatchingHomeTypeFilters(
            distanceMatched,
            foodType: _selectedFoodType,
            searchQuery: _searchQuery,
            category: _selectedCategory,
          )
        : distanceMatched;
    return campaignsForHomeReach(
      visible,
      reach: reach,
      buyerSocietyId: _buyerSocietyId,
      viewerUserId: _viewerUserId,
      nearbyRadiusKm: _cityReach.nearbyRadiusKm,
    );
  }

  Widget _buildPreOrdersSection() {
    if (_preOrdersLoading) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(20, 18, 20, 0),
        child: HomeFeedSkeleton(),
      );
    }
    return _buildPreOrderReachCarousel(
      title: 'Pre-orders Campaign in Your Society',
      campaigns: _mobileCampaignsForReach(HomeListingReach.inSociety),
    );
  }

  List<PreOrderCampaign> _webCampaignsFor(HomeListingReach reach) {
    if (!_showPreorderSections) return const [];
    return _mobileCampaignsForReach(reach);
  }

  Widget _buildPreOrderReachCarousel({
    required String title,
    required List<PreOrderCampaign> campaigns,
  }) {
    if (campaigns.isEmpty) return const SizedBox.shrink();
    final preview = campaigns.take(3).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: preorderText,
                  ),
                ),
              ),
              TextButton(
                onPressed: _openBuyerPreOrders,
                child: const Text(
                  'See all →',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0E5A47),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: HomePreOrderCampaignCard.cardHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: preview.length,
            separatorBuilder: (context, index) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final campaign = preview[index];
              return HomePreOrderCampaignCard(
                campaign: campaign,
                isOwn: campaign.sellerId == _viewerUserId,
                onTap: () => _openBuyerPreOrderDetail(campaign),
              );
            },
          ),
        ),
      ],
    );
  }

  void _openBuyerPreOrders() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BuyerPreOrdersScreen(
          hasRegularCart: _cart.isNotEmpty,
          cartItems: _cart,
          initialCampaigns: List<PreOrderCampaign>.from(_preOrderCampaigns),
          onCartChanged: () {
            CartController.instance.notify();
            if (mounted) setState(() {});
          },
        ),
      ),
    ).then((_) => _loadPreOrders());
  }

  Future<void> _openBuyerPreOrderDetail(PreOrderCampaign campaign) async {
    final placed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BuyerPreOrderDetailScreen(
          campaignId: campaign.id,
          initialCampaign: campaign,
          regularCartHasItems: _cart.isNotEmpty,
          cartItems: _cart,
          onCartChanged: () {
            CartController.instance.notify();
            if (mounted) setState(() {});
          },
        ),
      ),
    );
    if (placed == true) {
      _loadPreOrders();
    }
  }

  bool get _showEmptySocietyState {
    return _hasSuccessfullyLoaded &&
        _error == null &&
        _listings.isEmpty &&
        _preOrderCampaigns.isEmpty &&
        !_preOrdersLoading &&
        _searchQuery.isEmpty &&
        _selectedCategory == null;
  }

  Future<void> _startSellingFromHome() async {
    if (widget.onStartSelling != null) {
      widget.onStartSelling!();
      return;
    }
    try {
      final enabled = await SellerOnboarding.startSelling(context);
      if (!enabled || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Complete Seller Settings before selling is turned on'),
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

  void _openExploreNearby() {
    if (widget.onExploreNearby != null) {
      widget.onExploreNearby!();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ExploreNearbyScreen(onStartSelling: _startSellingFromHome),
      ),
    );
  }

  Widget _buildEmptySocietyState() {
    return StatusBanner(
      title: 'No sellers available in your society yet',
      message:
          'Be the first one to share homemade food in your community. Discover home food from nearby societies.',
      action: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          FilledButton(
            onPressed: _startSellingFromHome,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF0E5A47),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Start Selling'),
          ),
          OutlinedButton(
            onPressed: _openExploreNearby,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF0E5A47),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Explore Nearby'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return const AppHeader();
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE6EBE9)),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 10),
                  const Icon(
                    Icons.search_rounded,
                    color: Color(0xFF8A9491),
                    size: 18,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      key: const Key('home-search-field'),
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Search dishes, kitchens...',
                        hintStyle: TextStyle(
                          color: Color(0xFFADB5B2),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                        border: InputBorder.none,
                        isCollapsed: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      style: const TextStyle(
                        color: Color(0xFF223531),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (_searchQuery.isNotEmpty)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      onPressed: () {
                        _searchController.clear();
                      },
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Color(0xFF8A9491),
                        size: 16,
                      ),
                    )
                  else
                    const SizedBox(width: 8),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          VegFilterToggle(
            selected: _selectedFoodType == foodTypeVeg,
            onChanged: (vegOnly) {
              setState(() {
                _selectedFoodType = vegOnly ? foodTypeVeg : null;
              });
            },
          ),
        ],
      ),
    );
  }

  static const _homeFilterChips = [
    homeJustAddedFilter,
    'Breakfast',
    'Lunch',
    'Dinner',
    'Made to Order',
    'Pre-order',
    'Snacks',
    'Desserts',
  ];

  Widget _buildCategoryChips() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
      child: SizedBox(
        height: 38,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: _homeFilterChips.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) {
            final cat = _homeFilterChips[i];
            final isOrderType = cat == 'Made to Order' || cat == 'Pre-order';
            final isSelected = cat == homeJustAddedFilter
                ? _justAdded
                : isOrderType
                ? _listingType ==
                      (cat == 'Made to Order'
                          ? HomeListingType.madeToOrder
                          : HomeListingType.preOrder)
                : _selectedCategory == cat;
            return GestureDetector(
              key: Key('home-filter-chip-$cat'),
              onTap: () => _selectHomeFilter(cat),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFF0E5A47)
                      : const Color(0xFFF5F7F6),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF0E5A47)
                        : const Color(0xFFE0E5E3),
                  ),
                ),
                child: Text(
                  cat == homeJustAddedFilter ? '✨ Just Added' : cat,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : const Color(0xFF3A4644),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  List<Seller> get _societySellers =>
      sellersFromListings(_sellerPresenceForReach(HomeListingReach.inSociety));

  List<Seller> get _nearbySellers =>
      sellersFromListings(_sellerPresenceForReach(HomeListingReach.nearby));

  List<Seller> get _extendedSellers =>
      sellersFromListings(_sellerPresenceForReach(HomeListingReach.extended));

  Widget _buildHomeDiscoverySections() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSellerReachCarousel(
          key: const Key('home-sellers-in-society'),
          title: 'Top Sellers in Your Society',
          sellers: sellersFromListings(
            _sellerPresenceForReach(HomeListingReach.inSociety),
          ),
        ),
        _buildSpecialsSection(),
        if (_showPreorderSections) _buildPreOrdersSection(),
        _buildSellerReachCarousel(
          key: const Key('home-sellers-nearby'),
          title: 'Nearby Societies',
          subtitle: _cityReach.nearbyRadiusKm == null
              ? null
              : 'Sellers within ~${formatReachRadiusKm(_cityReach.nearbyRadiusKm!)} km',
          sellers: sellersFromListings(
            _sellerPresenceForReach(HomeListingReach.nearby),
          ),
        ),
        _buildReachSection(
          reach: HomeListingReach.nearby,
          listings: _mobileListingsForReach(HomeListingReach.nearby),
        ),
        if (_showPreorderSections)
          _buildPreOrderReachCarousel(
            title: 'Pre-orders Nearby',
            campaigns: _mobileCampaignsForReach(HomeListingReach.nearby),
          ),
        _buildSellerReachCarousel(
          key: const Key('home-sellers-extended'),
          title: 'More Around You',
          subtitle: _cityReach.extendedRadiusKm == null
              ? null
              : 'From other societies (within ~${formatReachRadiusKm(_cityReach.extendedRadiusKm!)} km)',
          sellers: sellersFromListings(
            _sellerPresenceForReach(HomeListingReach.extended),
          ),
        ),
        _buildReachSection(
          reach: HomeListingReach.extended,
          listings: _mobileListingsForReach(HomeListingReach.extended),
        ),
        if (_showPreorderSections)
          _buildPreOrderReachCarousel(
            title: 'Pre-orders Around You',
            campaigns: _mobileCampaignsForReach(HomeListingReach.extended),
          ),
      ],
    );
  }

  Widget _buildSellerReachCarousel({
    Key? key,
    required String title,
    String? subtitle,
    required List<Seller> sellers,
  }) {
    if (sellers.isEmpty) return const SizedBox.shrink();
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 22, 8, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF101617),
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF6A7774),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SellerListScreen(
                        title: title,
                        sellers: sellers,
                        onSellerTap: (seller) => _openSeller(
                          seller,
                          hideUnavailableDishes: !seller.hasOrderableItems,
                        ),
                      ),
                    ),
                  );
                },
                child: const Text(
                  'SEE ALL',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0E5A47),
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        PagedHorizontalList(
          height: 108,
          itemCount: sellers.length,
          separatorBuilder: (context, index) => const SizedBox(width: 16),
          itemBuilder: (_, i) => _SellerChip(
            seller: sellers[i],
            onTap: () => _openSeller(
              sellers[i],
              hideUnavailableDishes: !sellers[i].hasOrderableItems,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpecialsSection() {
    final listings = _mobileListingsForReach(HomeListingReach.inSociety);
    if (listings.isEmpty) return const SizedBox.shrink();
    if (_expandedReach == HomeListingReach.inSociety) {
      return _buildReachSection(
        reach: HomeListingReach.inSociety,
        title: "Today's Specials in Your Society",
        listings: listings,
      );
    }
    return _TodaysSpecialsSection(
      specials: listings.take(homeReachPreviewCount).toList(),
      showSeeAll: listings.length > homeReachPreviewCount,
      onSeeAll: () => _expandReach(HomeListingReach.inSociety),
      cartQtyFor: _cartQtyFor,
      onAdd: _addToCart,
      onRemove: _removeFromCart,
      onTap: _openDetail,
      onSellerTap: (food) => _openSeller(sellerFromListing(food)),
    );
  }

  void _expandReach(HomeListingReach reach) {
    setState(() => _expandedReach = reach);
  }

  void _collapseReach(HomeListingReach reach) {
    setState(() {
      if (_expandedReach == reach) _expandedReach = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final context = _reachSectionKeys[reach]?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        alignment: 0.08,
      );
    });
  }

  List<FoodItem> _listingsForReach(HomeListingReach reach) {
    return listingsForHomeReach(
      _filteredListings,
      reach: reach,
      buyerSocietyId: _buyerSocietyId,
      nearbyRadiusKm: _cityReach.nearbyRadiusKm,
    );
  }

  Widget _buildReachSection({
    required HomeListingReach reach,
    String? title,
    required List<FoodItem> listings,
  }) {
    if (listings.isEmpty) return const SizedBox.shrink();
    final expanded = _expandedReach == reach;
    final canToggle = listings.length > homeReachPreviewCount;
    final visible = expanded
        ? listings
        : listings.take(homeReachPreviewCount).toList();
    final seeAllKey = switch (reach) {
      HomeListingReach.inSociety => const Key('home-see-all-in-society'),
      HomeListingReach.nearby => const Key('home-see-all-nearby'),
      HomeListingReach.extended => const Key('home-see-all-extended'),
    };
    final showLessKey = switch (reach) {
      HomeListingReach.inSociety => const Key('home-show-less-in-society'),
      HomeListingReach.nearby => const Key('home-show-less-nearby'),
      HomeListingReach.extended => const Key('home-show-less-extended'),
    };
    const actionStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: Color(0xFF0E5A47),
      letterSpacing: 0.5,
    );
    final showTitle = title != null && title.isNotEmpty;
    return Column(
      key: _reachSectionKeys[reach],
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showTitle || canToggle)
          Padding(
            padding: EdgeInsets.fromLTRB(20, showTitle ? 22 : 8, 8, 14),
            child: Row(
              children: [
                Expanded(
                  child: showTitle
                      ? Text(
                          title,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF101617),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                if (canToggle)
                  TextButton(
                    key: expanded ? showLessKey : seeAllKey,
                    onPressed: () =>
                        expanded ? _collapseReach(reach) : _expandReach(reach),
                    child: expanded
                        ? const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('SHOW LESS', style: actionStyle),
                              Icon(
                                Icons.keyboard_arrow_up,
                                size: 16,
                                color: Color(0xFF0E5A47),
                              ),
                            ],
                          )
                        : const Text('SEE ALL', style: actionStyle),
                  ),
              ],
            ),
          )
        else
          const SizedBox(height: 12),
        if (expanded)
          ...visible.map(
            (food) => _AvailableItemTile(
              key: ValueKey('home-reach-tile-${food.id}'),
              food: food,
              cartQty: _cartQtyFor(food),
              onAdd: () => _addToCart(food),
              onRemove: () => _removeFromCart(food),
              onTap: () => _openDetail(food),
              onSellerTap: () => _openSeller(sellerFromListing(food)),
            ),
          )
        else
          PagedHorizontalList(
            height: 252,
            itemCount: visible.length,
            itemBuilder: (_, i) {
              final food = visible[i];
              return _SpecialCard(
                key: ValueKey('home-reach-card-${food.id}'),
                food: food,
                cartQty: _cartQtyFor(food),
                onAdd: () => _addToCart(food),
                onRemove: () => _removeFromCart(food),
                onTap: () => _openDetail(food),
                onSellerTap: () => _openSeller(sellerFromListing(food)),
              );
            },
          ),
      ],
    );
  }

  Widget _buildAvailableHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 8, 14),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _searchQuery.isEmpty
                  ? 'All Items'
                  : _available.isEmpty
                  ? 'No matches'
                  : _available.length == 1
                  ? '1 match'
                  : '${_available.length} matches',
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: Color(0xFF101617),
              ),
            ),
          ),
          if (_shouldPreviewAllItems)
            TextButton(
              key: const Key('home-see-all-items'),
              onPressed: () => setState(() => _showAllItems = true),
              child: const Text(
                'SEE ALL',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0E5A47),
                  letterSpacing: 0.5,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSeeAllItemsButton() {
    final remaining = _available.length - homeAllItemsPreviewCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: OutlinedButton(
          key: const Key('home-see-all-items-bottom'),
          onPressed: () => setState(() => _showAllItems = true),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF0E5A47),
            side: const BorderSide(color: Color(0xFFD4E8DF)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: Text(
            remaining == 1
                ? 'See all ($remaining more listing)'
                : 'See all ($remaining more listings)',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ),
      ),
    );
  }

  Widget _buildAvailableList() {
    if (_distanceFiltered.isEmpty && _filteredListings.isNotEmpty) {
      final distance = _effectiveDistance;
      final within = distance.societyOnly
          ? 'in your society'
          : distance.isExtended
          ? 'in the extended range'
          : 'within ${formatBuyerDistanceKm(distance.maxKm!)}';
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'No food available $within',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101617),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Try expanding your search radius.',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF6A7774),
                ),
              ),
              TextButton(
                key: const Key('home-distance-expand'),
                onPressed: () async {
                  final picked = await showHomeDistanceSheet(
                    context,
                    reach: _cityReach,
                    current: _effectiveDistance,
                  );
                  if (picked != null && mounted) {
                    setState(() => _distanceChoice = picked);
                  }
                },
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFF0E5A47),
                  padding: const EdgeInsets.only(left: 0),
                ),
                child: const Text(
                  'Expand distance',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_filteredListings.isEmpty) {
      return SliverToBoxAdapter(
        child: StatusBanner(
          message: _searchQuery.isNotEmpty
              ? 'No listings match "$_searchQuery".'
              : _selectedCategory != null
              ? 'No listings in $_selectedCategory yet.'
              : 'No listings yet. Be the first to add food from the seller dashboard.',
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, i) => _AvailableItemTile(
          key: ValueKey('home-all-item-${_visibleAvailable[i].id}'),
          food: _visibleAvailable[i],
          cartQty: _cartQtyFor(_visibleAvailable[i]),
          onAdd: () => _addToCart(_visibleAvailable[i]),
          onRemove: () => _removeFromCart(_visibleAvailable[i]),
          onTap: () => _openDetail(_visibleAvailable[i]),
          onSellerTap: () =>
              _openSeller(sellerFromListing(_visibleAvailable[i])),
        ),
        childCount: _visibleAvailable.length,
      ),
    );
  }
}

class _SellerChip extends StatelessWidget {
  const _SellerChip({required this.seller, required this.onTap});
  final Seller seller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: 72,
        height: 108,
        child: Column(
          children: [
            if (seller.hasOrderableItems)
              SellerAvatar(
                radius: 32,
                backgroundColor: seller.avatarColor,
                photoUrl: seller.profilePhotoUrl,
                ringColor: sellerSellingRingColor,
                ringWidth: 2.4,
                fallback: Icon(
                  seller.avatarIcon,
                  color: const Color(0xFF3A4644),
                  size: 28,
                ),
              )
            else
              SellerAvatar(
                radius: 32,
                backgroundColor: seller.avatarColor,
                photoUrl: seller.profilePhotoUrl,
                ringColor: const Color(0xFFD5DCDA),
                ringWidth: 1.5,
                muted: true,
                fallback: Icon(
                  seller.avatarIcon,
                  color: const Color(0xFF6A7774),
                  size: 28,
                ),
              ),
            const SizedBox(height: 4),
            if (seller.hasOrderableItems)
              SizedBox(
                width: 72,
                height: 32,
                child: Text(
                  seller.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3A4644),
                    height: 1.1,
                  ),
                ),
              )
            else ...[
              SizedBox(
                width: 72,
                child: Text(
                  seller.name,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF3A4644),
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(
                width: 72,
                child: Text(
                  sellerNotAvailableLabel,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8A9491),
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Today's Specials carousel. Dots under the row show there is more to scroll.
class _TodaysSpecialsSection extends StatelessWidget {
  const _TodaysSpecialsSection({
    required this.specials,
    required this.cartQtyFor,
    required this.onAdd,
    required this.onRemove,
    required this.onTap,
    required this.onSellerTap,
    this.showSeeAll = false,
    this.onSeeAll,
  });

  final List<FoodItem> specials;
  final int Function(FoodItem food) cartQtyFor;
  final void Function(FoodItem food) onAdd;
  final void Function(FoodItem food) onRemove;
  final void Function(FoodItem food) onTap;
  final void Function(FoodItem food) onSellerTap;
  final bool showSeeAll;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 8, 2),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  "Today's Specials in Your Society",
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101617),
                  ),
                ),
              ),
              if (showSeeAll)
                TextButton(
                  key: const Key('home-see-all-in-society'),
                  onPressed: onSeeAll,
                  child: const Text(
                    'SEE ALL',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0E5A47),
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        PagedHorizontalList(
          height: 252,
          itemCount: specials.length,
          itemBuilder: (_, i) {
            final food = specials[i];
            return _SpecialCard(
              key: ValueKey('home-special-card-${food.id}'),
              food: food,
              cartQty: cartQtyFor(food),
              onAdd: () => onAdd(food),
              onRemove: () => onRemove(food),
              onTap: () => onTap(food),
              onSellerTap: () => onSellerTap(food),
            );
          },
        ),
      ],
    );
  }
}

class _SpecialCard extends StatelessWidget {
  const _SpecialCard({
    super.key,
    required this.food,
    required this.cartQty,
    required this.onAdd,
    required this.onRemove,
    required this.onTap,
    required this.onSellerTap,
  });

  final FoodItem food;
  final int cartQty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onTap;
  final VoidCallback onSellerTap;

  @override
  Widget build(BuildContext context) {
    final isDark = food.bgColor.computeLuminance() < 0.4;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 190,
        decoration: BoxDecoration(
          color: food.bgColor,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListingCompactCardHeader(food: food, isDark: isDark),
            Expanded(
              child: Center(
                child: ListingImage(
                  food: food,
                  width: 112,
                  height: 112,
                  borderRadius: 0,
                  iconSize: 60,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              child: Text(
                food.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : const Color(0xFF101617),
                  height: 1.2,
                ),
              ),
            ),
            if (food.isMadeToOrder)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 2),
                child: MadeToOrderHint(
                  food: food,
                  compact: true,
                  timingOnly: true,
                ),
              ),
            if (food.isRecurringReadyNow)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 2),
                child: RecurringAvailabilityHint(food: food, compact: true),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: onSellerTap,
                          child: Text(
                            'By ${food.sellerName}',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.25,
                              color: isDark
                                  ? Colors.white
                                  : const Color(0xFF0E5A47),
                              decoration: TextDecoration.underline,
                              decorationColor: isDark
                                  ? Colors.white
                                  : const Color(0xFF0E5A47),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (food.homePlaceLabel.isNotEmpty)
                          Text(
                            food.homePlaceLabel,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.25,
                              color: isDark
                                  ? Colors.white70
                                  : const Color(0xFF6A7774),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (listingSoldCaption(food.quantitySold).isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 6, top: 1),
                      child: Text(
                        listingSoldCaption(food.quantitySold),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.25,
                          fontWeight: FontWeight.w600,
                          color: isDark
                              ? Colors.white70
                              : const Color(0xFF6A7774),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 10, 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: ListingCompactPriceRow(food: food, isDark: isDark),
                  ),
                  const SizedBox(width: 6),
                  MarketplacePurchaseSlot(
                        food: food,
                        cartQty: cartQty,
                        soldOut: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFD94F4F),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Text(
                            'SOLD OUT',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        addButton: GestureDetector(
                          onTap: onAdd,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0E5A47),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Text(
                              'Add',
                              softWrap: false,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        qtyStepper: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0E5A47),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              GestureDetector(
                                onTap: onRemove,
                                child: const Icon(
                                  Icons.remove,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                child: Text(
                                  '$cartQty',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: onAdd,
                                child: const Icon(
                                  Icons.add,
                                  size: 18,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AvailableItemTile extends StatelessWidget {
  const _AvailableItemTile({
    super.key,
    required this.food,
    required this.cartQty,
    required this.onAdd,
    required this.onRemove,
    required this.onTap,
    required this.onSellerTap,
  });

  final FoodItem food;
  final int cartQty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onTap;
  final VoidCallback onSellerTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFEAEFED)),
        ),
        child: Row(
          children: [
            ListingImage(food: food, width: 72, height: 72, iconSize: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              food.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF101617),
                                height: 1.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                ListingTypeBadge(food: food, dense: true),
                                if (food.isNewListing()) ...[
                                  const SizedBox(width: 6),
                                  const ListingNewChip(dense: true),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₹${food.price.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0E5A47),
                            ),
                          ),
                          ListingPortionCaption(food: food),
                          if (listingSoldCaption(
                            food.quantitySold,
                          ).isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              listingSoldCaption(food.quantitySold),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF6A7774),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                  MadeToOrderHint(food: food, compact: true),
                  RecurringAvailabilityHint(food: food, compact: true),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: GestureDetector(
                                onTap: onSellerTap,
                                child: Text(
                                  food.sellerName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF0E5A47),
                                    decoration: TextDecoration.underline,
                                    decorationColor: Color(0xFF0E5A47),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            Flexible(
                              child: Text(
                                ', ${food.homePlaceLabel}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF6A7774),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      ListingRatingMark(food: food, showNewBadge: false),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (showListingScheduleChipOnHomeCard(food)) ...[
                        Flexible(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE8F5EE),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.schedule_rounded,
                                  size: 13,
                                  color: Color(0xFF0E5A47),
                                ),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    listingScheduleCaption(food),
                                    softWrap: true,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      height: 1.25,
                                      color: Color(0xFF0E5A47),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: MarketplacePurchaseSlot(
                            food: food,
                            cartQty: cartQty,
                            soldOut: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFD94F4F),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'SOLD OUT',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            addButton: GestureDetector(
                              onTap: onAdd,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0E5A47),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text(
                                  'Add',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            qtyStepper: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0E5A47),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  GestureDetector(
                                    onTap: onRemove,
                                    child: const Icon(
                                      Icons.remove,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                    ),
                                    child: Text(
                                      '$cartQty',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    onTap: onAdd,
                                    child: const Icon(
                                      Icons.add,
                                      size: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
