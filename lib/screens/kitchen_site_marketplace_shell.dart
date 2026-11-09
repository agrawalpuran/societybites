import 'dart:async';

import 'package:flutter/material.dart';

import '../models/data.dart';
import '../models/kitchen_hours.dart';
import '../models/storefront_kitchen.dart';
import '../navigation/kitchen_site_navigation.dart';
import '../services/api_service.dart';
import '../services/cart_controller.dart';
import '../services/session_service.dart';
import '../utils/listing_catalog_order.dart';
import '../utils/listing_portion_label.dart';
import '../web/web_breakpoints.dart';
import '../web/web_cart_dock.dart';
import '../web/web_marketplace_home.dart';
import '../web/web_shell_header.dart';
import '../widgets/guest_order_auth.dart';
import '../widgets/listing_variant_picker_sheet.dart';
import '../widgets/one_seller_cart.dart';
import 'buyer_preorder_detail_screen.dart';
import 'food_detail_screen.dart';
import 'home_listing_filter.dart';
import 'login_screen.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';
import 'seller_dashboard_screen.dart';
import '../models/listing_categories.dart';
import '../widgets/storefront_theme_scope.dart';

/// Full SocietyEats web home layout scoped to one branded kitchen.
class KitchenSiteMarketplaceShell extends StatefulWidget {
  const KitchenSiteMarketplaceShell({
    super.key,
    required this.slug,
    required this.payload,
  });

  final String slug;
  final StorefrontKitchenPayload payload;

  @override
  State<KitchenSiteMarketplaceShell> createState() =>
      _KitchenSiteMarketplaceShellState();
}

class _KitchenSiteMarketplaceShellState
    extends State<KitchenSiteMarketplaceShell> {
  late StorefrontKitchenPayload _payload;
  List<FoodItem> _listings = [];
  List<PreOrderCampaign> _campaigns = [];
  bool _loading = true;
  bool _hasLoaded = false;
  bool _preOrdersLoading = false;
  String? _error;
  String _searchQuery = '';
  String? _selectedCategory;
  String? _selectedFoodType;
  HomeListingType _listingType = HomeListingType.all;
  var _justAdded = false;
  int _navIndex = 0;
  bool? _signedIn;
  String? _viewerUserId;
  var _ordersMounted = false;
  var _dashboardMounted = false;
  var _profileMounted = false;
  var _kitchenAttentionCount = 0;
  final _ordersKey = GlobalKey<OrdersScreenState>();
  final _dashboardKey = GlobalKey<SellerDashboardScreenState>();
  final _profileKey = GlobalKey<ProfileScreenState>();

  List<CartItem> get _cart => CartController.instance.items;

  static const _filterChips = [
    homeJustAddedFilter,
    'Breakfast',
    'Lunch',
    'Dinner',
    'Made to Order',
    'Pre-order',
    'Snacks',
    'Dairy',
    'Pickle',
    'Desserts',
  ];

  @override
  void initState() {
    super.initState();
    _payload = widget.payload;
    CartController.instance.addListener(_onCart);
    CartController.instance.onSelectShellTab = _selectTab;
    CartController.instance.onShowOrdersAfterPlace = () => _selectTab(1);
    unawaited(_refreshSignedIn());
    unawaited(_loadCatalog());
  }

  @override
  void dispose() {
    CartController.instance.removeListener(_onCart);
    if (CartController.instance.onSelectShellTab == _selectTab) {
      CartController.instance.onSelectShellTab = null;
    }
    if (CartController.instance.onShowOrdersAfterPlace == () => _selectTab(1)) {
      CartController.instance.onShowOrdersAfterPlace = null;
    }
    super.dispose();
  }

  void _onCart() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshSignedIn() async {
    final token = await SessionService.getToken();
    final refresh = await SessionService.getRefreshToken();
    final signedIn =
        (token != null && token.isNotEmpty) ||
        (refresh != null && refresh.isNotEmpty);
    final userId = await SessionService.getUserId();
    if (!mounted) return;
    setState(() {
      _signedIn = signedIn;
      _viewerUserId = userId;
    });
    if (signedIn) {
      await _loadCatalog(background: true);
    }
  }

  Future<void> _loadCatalog({bool background = false}) async {
    if (!background) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      setState(() => _preOrdersLoading = true);
    }
    try {
      final slugRaw = await ApiService.getPublicKitchenBySlug(widget.slug);
      _payload = StorefrontKitchenPayload.fromJson(slugRaw);
      final sellerId = _payload.sellerId;
      var listingRaw = <Map<String, dynamic>>[];
      var campaignRaw = <Map<String, dynamic>>[];

      final societyId = await SessionService.getSocietyId();
      if (societyId != null && societyId.isNotEmpty) {
        final responses = await Future.wait([
          ApiService.getListings(
            societyId: societyId,
            sellerId: sellerId,
            catalogType: 'REGULAR',
            status: 'discoverable',
          ),
          ApiService.getPreOrderCampaigns(
            societyId: societyId,
            sellerId: sellerId,
            status: 'open',
          ),
        ]);
        listingRaw = responses[0];
        campaignRaw = responses[1];
      } else {
        listingRaw = _payload.listings;
        campaignRaw = _payload.campaigns;
      }

      var products = sortFoodItemsByCatalogOrder(
        listingRaw
            .map(FoodItem.fromJson)
            .where((item) => item.sellerId == sellerId)
            .where((item) => (item.isActive || item.isExpired) && !item.isPreOrder)
            .toList(),
      );
      if (products.isEmpty) {
        products = _payload.listings.map(FoodItem.fromJson).toList();
      }

      final campaigns = campaignRaw
          .map(PreOrderCampaign.fromJson)
          .where((c) => c.sellerId == sellerId)
          .toList()
        ..sort((a, b) => a.orderCutoffAt.compareTo(b.orderCutoffAt));

      if (!mounted) return;
      setState(() {
        _listings = products;
        _campaigns = campaigns;
        _loading = false;
        _preOrdersLoading = false;
        _hasLoaded = true;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      if (!_hasLoaded) {
        setState(() {
          _error = ApiService.userFacingError(error);
          _loading = false;
          _preOrdersLoading = false;
        });
      } else {
        setState(() => _preOrdersLoading = false);
      }
    }
  }

  List<FoodItem> get _filtered {
    return applyHomeListingFilters(
      _listings,
      category: _selectedCategory,
      searchQuery: _searchQuery,
      foodType: _selectedFoodType,
      listingType: _listingType,
      justAdded: _justAdded,
    );
  }

  List<FoodItem> get _readyNow {
    return _filtered.where((food) {
      return !food.isMadeToOrder &&
          !food.isPreOrder &&
          !food.isPreOrderCatalog &&
          food.canAddToCart;
    }).toList();
  }

  List<FoodItem> get _madeToOrder {
    return _filtered.where((food) => food.isMadeToOrder).toList();
  }

  List<FoodItem> _heroFoods() {
    final withImages = _listings.where((food) {
      final url = food.imageUrl?.trim();
      return url != null && url.isNotEmpty && url != 'null';
    }).take(2);
    final foods = withImages.toList();
    if (foods.isNotEmpty) return foods;
    if (_listings.isNotEmpty) return [_listings.first];
    return const [];
  }

  Map<String, int> _categoryCounts() {
    final counts = <String, int>{};
    for (final category in _filterChips) {
      if (category == homeJustAddedFilter ||
          category == 'Made to Order' ||
          category == 'Pre-order') {
        continue;
      }
      counts[category] = _listings
          .where(
            (food) => listingMatchesHomeCategory(
              food.listingCategories,
              selectedCategory: category,
              legacyCategory: food.category,
            ),
          )
          .length;
    }
    return counts;
  }

  Set<String> get _activeFilterLabels => {
    ?_selectedCategory,
    if (_justAdded) homeJustAddedFilter,
    if (_listingType == HomeListingType.madeToOrder) 'Made to Order',
    if (_listingType == HomeListingType.preOrder) 'Pre-order',
  };

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

  int _cartQtyForExact(FoodItem food) {
    final idx = _cart.indexWhere((c) => c.food.id == food.id);
    return idx != -1 ? _cart[idx].quantity : 0;
  }

  int _cartQtyFor(FoodItem food) {
    final groupId = food.variantGroupId?.trim();
    if (groupId != null && groupId.isNotEmpty) {
      return _cart
          .where((c) => c.food.variantGroupId?.trim() == groupId)
          .fold<int>(0, (sum, c) => sum + c.quantity);
    }
    return _cartQtyForExact(food);
  }

  Future<void> _adjustCartQuantity(FoodItem food, int delta) async {
    if (delta < 0) {
      _removeFromCart(food);
      return;
    }
    if (listingHasSizeOptions(food)) {
      await _addVariantViaPicker(food);
      return;
    }
    if (_cartQtyFor(food) > 0) {
      await _incrementCartLine(food);
      return;
    }
    await _addToCart(food);
  }

  Future<bool> _needsAuth() async {
    if (await SessionService.isOnboarded()) return false;
    final allowed = await handleGuestKitchenAddToCart(context);
    return !allowed;
  }

  Future<void> _addVariantViaPicker(FoodItem seed) async {
    if (seed.isKitchenClosed) {
      showKitchenClosedMessage(context);
      return;
    }
    if (await _needsAuth()) return;
    if (!mounted) return;
    final allowed = await confirmCartSellerAllowed(
      context,
      cart: _cart,
      sellerId: seed.sellerId,
      sellerName: seed.sellerName,
      alsoBlockedBy: CartController.instance.items,
      onViewCart: () => CartController.instance.openCheckout(context),
    );
    if (!allowed || !mounted) return;
    final result = await ListingVariantPickerSheet.show(context, seed: seed);
    if (result == null || !mounted) return;
    await _addToCart(result.food, quantity: result.quantity, sellerConfirmed: true);
  }

  Future<void> _incrementCartLine(FoodItem food) async {
    if (food.isKitchenClosed) {
      showKitchenClosedMessage(context);
      return;
    }
    if (!food.canAddToCart) return;
    final current = _cartQtyForExact(food);
    if (current >= food.buyerMaxCartQuantity) return;
    setState(() {
      final existing = _cart.indexWhere((c) => c.food.id == food.id);
      if (existing != -1) {
        _cart[existing] = CartItem(food: food, quantity: current + 1);
      }
    });
    CartController.instance.notify();
  }

  Future<void> _addToCart(
    FoodItem food, {
    int quantity = 1,
    bool sellerConfirmed = false,
  }) async {
    if (food.isKitchenClosed) {
      showKitchenClosedMessage(context);
      return;
    }
    if (!food.canAddToCart) return;
    if (!sellerConfirmed && await _needsAuth()) return;
    if (!mounted) return;
    if (!sellerConfirmed) {
      final allowed = await confirmCartSellerAllowed(
        context,
        cart: _cart,
        sellerId: food.sellerId,
        sellerName: food.sellerName,
        alsoBlockedBy: CartController.instance.items,
        onViewCart: () => CartController.instance.openCheckout(context),
      );
      if (!allowed || !mounted) return;
    }
    final mixConflict = cartAvailabilityConflict(_cart, food);
    if (mixConflict != null) return;
    final current = _cartQtyForExact(food);
    final maxQty = food.buyerMaxCartQuantity;
    final nextQty = (current + quantity).clamp(1, maxQty);
    setState(() {
      final existing = _cart.indexWhere((c) => c.food.id == food.id);
      if (existing != -1) {
        _cart[existing] = CartItem(food: food, quantity: nextQty);
      } else {
        _cart.add(CartItem(food: food, quantity: nextQty));
      }
    });
    CartController.instance.notify();
    ApiService.prefetchPlatformFee();
  }

  void _removeFromCart(FoodItem food) {
    setState(() {
      final groupId = food.variantGroupId?.trim();
      final existing = (groupId != null && groupId.isNotEmpty)
          ? _cart.lastIndexWhere(
              (c) => c.food.variantGroupId?.trim() == groupId,
            )
          : _cart.indexWhere((c) => c.food.id == food.id);
      if (existing == -1) return;
      final qty = _cart[existing].quantity - 1;
      if (qty <= 0) {
        _cart.removeAt(existing);
      } else {
        _cart[existing] = CartItem(food: food, quantity: qty);
      }
    });
    CartController.instance.notify();
  }

  void _openDetail(FoodItem food) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => FoodDetailScreen(
          food: food,
          requireAuthToOrder: true,
          onSellerTap: () {},
        ),
      ),
    );
  }

  Future<void> _openCampaign(PreOrderCampaign campaign) async {
    final placed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => BuyerPreOrderDetailScreen(
          campaignId: campaign.id,
          initialCampaign: campaign,
          regularCartHasItems: _cart.isNotEmpty,
          cartItems: _cart,
          onCartChanged: CartController.instance.notify,
        ),
      ),
    );
    if (placed == true && mounted) {
      await _loadCatalog(background: true);
    }
  }

  void _selectTab(int index) {
    if (_navIndex == index) return;
    setState(() {
      _navIndex = index;
      if (index == 1) _ordersMounted = true;
      if (index == 2) _dashboardMounted = true;
      if (index == 3) _profileMounted = true;
    });
  }

  void _openSignIn() {
    unawaited(KitchenSiteNavigation.holdKitchenSlug(widget.slug));
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    ).then((_) => _refreshSignedIn());
  }

  bool get _showEmpty {
    return _hasLoaded &&
        _error == null &&
        _listings.isEmpty &&
        _campaigns.isEmpty &&
        _searchQuery.isEmpty &&
        _selectedCategory == null;
  }

  Widget _buildMarketplace() {
    final payload = _payload;
    final tagline = payload.branding.tagline?.trim();
    final banner = payload.branding.bannerUrl?.trim();
    return WebMarketplaceHome(
      kitchenSiteMode: true,
      kitchenHeroEyebrow: payload.sellerName,
      kitchenHeroTitle: 'Order from\n${payload.sellerName}',
      kitchenHeroSubtitle: tagline?.isNotEmpty == true
          ? tagline
          : '${payload.societyName} · Pickup on SocietyEats',
      kitchenBannerUrl:
          banner != null && banner.isNotEmpty ? banner : null,
      isInitialLoading: _loading && !_hasLoaded,
      isBackgroundRefreshing: false,
      isSlow: false,
      errorMessage: _error,
      showEmptySociety: _showEmpty,
      searching: _searchQuery.isNotEmpty,
      searchQuery: _searchQuery,
      selectedCategory: _selectedCategory,
      categories: _filterChips,
      categoryCounts: _categoryCounts(),
      heroFoods: _heroFoods(),
      allFiltered: _filtered,
      highlightSellers: const [],
      sellerListings: _listings,
      readyNow: _readyNow,
      madeToOrder: _madeToOrder,
      nearbyListings: const [],
      nearbySellers: const [],
      nearbySubtitle: null,
      extendedListings: const [],
      extendedSellers: const [],
      extendedSubtitle: null,
      otherListings: const [],
      inSocietyPreorders: _campaigns,
      nearbyPreorders: const [],
      extendedPreorders: const [],
      preordersLoading: _preOrdersLoading,
      viewerUserId: _viewerUserId,
      expandedReach: null,
      cartQtyFor: _cartQtyFor,
      onAdd: (food) => _adjustCartQuantity(food, 1),
      onRemove: (food) => _adjustCartQuantity(food, -1),
      onOpenFood: _openDetail,
      onOpenSeller: (_) {},
      onOpenCampaign: _openCampaign,
      onSeePreorders: () {},
      onCategorySelected: _selectHomeFilter,
      onExpandReach: (_) {},
      onCollapseReach: (_) {},
      onRetry: () => _loadCatalog(),
      onRefresh: () => _loadCatalog(),
      onStartSelling: () => _selectTab(2),
      onExploreNearby: () {},
      onSelectTab: _selectTab,
      listingType: _listingType,
      activeFilterLabels: _activeFilterLabels,
      onListingTypeSelected: (type) => setState(() => _listingType = type),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wide = useWebMarketplaceLayout(context);
    final marketplace = _navIndex == 0
        ? _buildMarketplace()
        : _navIndex == 1 && _ordersMounted
        ? OrdersScreen(key: _ordersKey, onExploreHome: () => _selectTab(0))
        : _navIndex == 2 && _dashboardMounted
        ? SellerDashboardScreen(
            key: _dashboardKey,
            onKitchenAttentionCount: (count) {
              if (mounted && count != _kitchenAttentionCount) {
                setState(() => _kitchenAttentionCount = count);
              }
            },
          )
        : _navIndex == 3 && _profileMounted
        ? ProfileScreen(key: _profileKey, onSelectTab: _selectTab)
        : const SizedBox.shrink();

    final body = Column(
      children: [
        if (wide)
          WebShellHeader(
            kitchenSiteMode: true,
            kitchenBrandName: () {
              final tagline = _payload.branding.tagline?.trim();
              if (tagline != null && tagline.isNotEmpty) return tagline;
              return _payload.sellerName;
            }(),
            kitchenBrandLogoUrl:
                _payload.seller['profilePhotoUrl']?.toString(),
            selectedTab: _navIndex,
            kitchenAttentionCount: _kitchenAttentionCount,
            signedIn: _signedIn,
            selectedFoodType: _selectedFoodType,
            onSelectTab: _selectTab,
            onSignIn: _openSignIn,
            onFoodTypeChanged: (value) {
              setState(() => _selectedFoodType = value);
              if (_navIndex != 0) _selectTab(0);
            },
            onSearchChanged: (value) {
              setState(() => _searchQuery = value);
              if (_navIndex != 0) _selectTab(0);
            },
          ),
        Expanded(child: marketplace),
        if (wide) const WebCartDock(),
      ],
    );

    return StorefrontThemeScope(
      accentHex: _payload.branding.accentColor,
      child: Scaffold(
        backgroundColor: webPageBackground,
        body: body,
      ),
    );
  }
}
