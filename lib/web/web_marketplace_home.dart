import 'package:flutter/material.dart';

import '../models/data.dart';
import '../models/legal_documents.dart';
import '../screens/help_center_screen.dart';
import '../models/selling_reach.dart';
import '../screens/home_listing_filter.dart';
import '../widgets/home_distance_chip.dart';
import '../screens/legal_screen.dart';
import '../widgets/listing_image.dart';
import '../widgets/preorder_widgets.dart';
import 'web_breakpoints.dart';
import 'web_category_row.dart';
import 'web_food_card.dart';
import 'web_footer.dart';
import 'web_marketplace_states.dart';
import 'web_seller_card.dart';
import 'web_trust_band.dart';
import '../widgets/feed_refresh_bar.dart';

class WebMarketplaceHome extends StatefulWidget {
  const WebMarketplaceHome({
    super.key,
    required this.isInitialLoading,
    this.isBackgroundRefreshing = false,
    required this.isSlow,
    required this.errorMessage,
    required this.showEmptySociety,
    required this.searching,
    required this.searchQuery,
    required this.selectedCategory,
    required this.categories,
    required this.categoryCounts,
    required this.heroFoods,
    required this.allFiltered,
    required this.highlights,
    required this.highlightSellers,
    required this.sellerListings,
    required this.readyNow,
    required this.madeToOrder,
    required this.nearbyListings,
    required this.nearbySellers,
    required this.nearbySubtitle,
    required this.extendedListings,
    required this.extendedSellers,
    required this.extendedSubtitle,
    required this.otherListings,
    required this.inSocietyPreorders,
    required this.nearbyPreorders,
    required this.extendedPreorders,
    required this.preordersLoading,
    required this.viewerUserId,
    required this.expandedReach,
    required this.cartQtyFor,
    required this.onAdd,
    required this.onRemove,
    required this.onOpenFood,
    required this.onOpenSeller,
    required this.onOpenCampaign,
    required this.onSeePreorders,
    required this.onCategorySelected,
    required this.onExpandReach,
    required this.onCollapseReach,
    required this.onRetry,
    required this.onRefresh,
    required this.onStartSelling,
    required this.onExploreNearby,
    required this.onSelectTab,
    this.listingType = HomeListingType.all,
    this.distanceReach,
    this.distanceChoice,
    this.dishCount = 0,
    this.onDistanceSelected,
    this.onListingTypeSelected,
    this.activeFilterLabels,
  });

  final bool isInitialLoading;
  final bool isBackgroundRefreshing;
  final bool isSlow;
  final String? errorMessage;
  final bool showEmptySociety;
  final bool searching;
  final String searchQuery;
  final String? selectedCategory;
  final List<String> categories;
  final Map<String, int> categoryCounts;
  final List<FoodItem> heroFoods;
  final List<FoodItem> allFiltered;
  final List<FoodItem> highlights;
  final List<Seller> highlightSellers;
  final List<FoodItem> sellerListings;
  final List<FoodItem> readyNow;
  final List<FoodItem> madeToOrder;
  final List<FoodItem> nearbyListings;
  final List<Seller> nearbySellers;
  final String? nearbySubtitle;
  final List<FoodItem> extendedListings;
  final List<Seller> extendedSellers;
  final String? extendedSubtitle;
  final List<FoodItem> otherListings;
  final List<PreOrderCampaign> inSocietyPreorders;
  final List<PreOrderCampaign> nearbyPreorders;
  final List<PreOrderCampaign> extendedPreorders;
  final bool preordersLoading;
  final String? viewerUserId;
  final HomeListingReach? expandedReach;
  final int Function(FoodItem food) cartQtyFor;
  final void Function(FoodItem food) onAdd;
  final void Function(FoodItem food) onRemove;
  final void Function(FoodItem food) onOpenFood;
  final void Function(Seller seller) onOpenSeller;
  final void Function(PreOrderCampaign campaign) onOpenCampaign;
  final VoidCallback onSeePreorders;
  final ValueChanged<String?> onCategorySelected;
  final ValueChanged<HomeListingReach> onExpandReach;
  final ValueChanged<HomeListingReach> onCollapseReach;
  final VoidCallback onRetry;
  final Future<void> Function() onRefresh;
  final VoidCallback onStartSelling;
  final VoidCallback onExploreNearby;
  final ValueChanged<int> onSelectTab;
  final HomeListingType listingType;
  final SellingReach? distanceReach;
  final BuyerDistanceChoice? distanceChoice;
  final int dishCount;
  final ValueChanged<BuyerDistanceChoice>? onDistanceSelected;
  final ValueChanged<HomeListingType>? onListingTypeSelected;
  final Set<String>? activeFilterLabels;

  @override
  State<WebMarketplaceHome> createState() => _WebMarketplaceHomeState();
}

class _WebMarketplaceHomeState extends State<WebMarketplaceHome> {
  final _readyKey = GlobalKey();
  final _madeKey = GlobalKey();
  final _preorderKey = GlobalKey();
  final _nearbyKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('web-marketplace-home'),
      backgroundColor: webPageBackground,
      body: RefreshIndicator(
        color: webGreen,
        onRefresh: widget.onRefresh,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final pad = webPagePadding(width);
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(pad, 22, pad, 48),
              children: [
                FeedRefreshBar(visible: widget.isBackgroundRefreshing),
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: webFrameMaxWidth,
                    ),
                    child: widget.isInitialLoading
                        ? WebMarketplaceSkeleton(
                            isSlow: widget.isSlow,
                            onRetry: widget.onRetry,
                          )
                        : _body(width),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _body(double width) {
    if (widget.errorMessage != null &&
        widget.highlights.isEmpty &&
        widget.readyNow.isEmpty &&
        widget.madeToOrder.isEmpty &&
        widget.nearbyListings.isEmpty &&
        widget.inSocietyPreorders.isEmpty) {
      return Column(
        children: [
          WebMarketplaceError(
            message: widget.errorMessage!,
            onRetry: widget.onRetry,
          ),
          const SizedBox(height: 28),
          _footer(),
        ],
      );
    }

    if (widget.showEmptySociety) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _hero(width),
          const SizedBox(height: 22),
          _emptySociety(),
          const SizedBox(height: 28),
          const WebTrustBand(),
          const SizedBox(height: 8),
          _footer(),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.errorMessage != null) ...[
          WebMarketplaceError(
            message: widget.errorMessage!,
            onRetry: widget.onRetry,
          ),
          const SizedBox(height: 18),
        ],
        _hero(width),
        if (_hasDistanceControl) ...[
          const SizedBox(height: 16),
          HomeDistanceChip(
            padding: EdgeInsets.zero,
            reach: widget.distanceReach!,
            selected: widget.distanceChoice,
            itemCount: widget.dishCount,
            listingType: widget.listingType,
            onSelected: widget.onDistanceSelected!,
            onListingTypeSelected: widget.onListingTypeSelected,
          ),
        ],
        if (!widget.searching) ...[
          const SizedBox(height: 28),
          const WebSectionHeader(
            eyebrow: 'Explore by category',
            title: 'What are you looking for?',
          ),
          const SizedBox(height: 14),
          WebCategoryRow(
            categories: widget.categories,
            selectedCategory: widget.selectedCategory,
            counts: widget.categoryCounts,
            onSelected: widget.onCategorySelected,
            activeLabels: widget.activeFilterLabels,
          ),
          _listingSections(),
        ] else ...[
          const SizedBox(height: 28),
          WebSectionHeader(eyebrow: 'Search', title: _searchTitle()),
          const SizedBox(height: 14),
          if (widget.allFiltered.isEmpty)
            _emptyCopy(_emptyMessage())
          else
            WebFoodGrid(
              items: widget.allFiltered,
              cartQtyFor: widget.cartQtyFor,
              onAdd: widget.onAdd,
              onRemove: widget.onRemove,
              onOpen: widget.onOpenFood,
              onSeller: (food) => widget.onOpenSeller(sellerFromListing(food)),
            ),
        ],
        const SizedBox(height: 36),
        const WebTrustBand(),
        _footer(),
      ],
    );
  }

  bool get _hasDistanceControl =>
      widget.distanceReach != null &&
      widget.onDistanceSelected != null &&
      widget.onListingTypeSelected != null;

  Widget _listingSections() {
    final sections = <Widget>[
      if (widget.highlights.isNotEmpty)
        _foodSection(
          eyebrow: "In your society",
          title: "Today's kitchen highlights",
          items: widget.highlights,
          reach: HomeListingReach.inSociety,
        ),
      if (widget.highlightSellers.isNotEmpty)
        _sellerSection(
          eyebrow: 'In your society',
          title: 'Top resident kitchens',
          sellers: widget.highlightSellers,
        ),
      if (widget.readyNow.isNotEmpty) _readySection(),
      if (widget.madeToOrder.isNotEmpty)
        _foodSection(
          key: _madeKey,
          eyebrow: 'Made to order',
          title: 'Cooked when you ask',
          items: widget.madeToOrder,
        ),
      if (widget.preordersLoading || widget.inSocietyPreorders.isNotEmpty)
        _preorderSection(
          key: _preorderKey,
          title: 'Pre-orders in your society',
          campaigns: widget.inSocietyPreorders,
        ),
      if (widget.nearbySellers.isNotEmpty || widget.nearbyListings.isNotEmpty)
        _reachBlock(
          key: _nearbyKey,
          eyebrow: 'Nearby societies',
          title: 'Nearby kitchens',
          subtitle: widget.nearbySubtitle,
          sellers: widget.nearbySellers,
          items: widget.nearbyListings,
          reach: HomeListingReach.nearby,
        ),
      if (widget.nearbyPreorders.isNotEmpty)
        _preorderSection(
          title: 'Pre-orders nearby',
          campaigns: widget.nearbyPreorders,
        ),
      if (widget.extendedSellers.isNotEmpty ||
          widget.extendedListings.isNotEmpty)
        _reachBlock(
          eyebrow: 'Further out',
          title: 'More around you',
          subtitle: widget.extendedSubtitle,
          sellers: widget.extendedSellers,
          items: widget.extendedListings,
          reach: HomeListingReach.extended,
        ),
      if (widget.extendedPreorders.isNotEmpty)
        _preorderSection(
          title: 'Pre-orders around you',
          campaigns: widget.extendedPreorders,
        ),
      if (widget.otherListings.isNotEmpty)
        _foodSection(
          eyebrow: 'Also available',
          title: 'More listings',
          items: widget.otherListings,
        ),
    ];

    if (sections.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 22),
        child: _emptyCopy(_emptyMessage()),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: sections,
    );
  }

  Widget _hero(double width) {
    final desktop = width >= 980;
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'YOUR SOCIETY',
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w800,
            color: webGreen,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Fresh flavors from\nyour Society and\nneighbourhood.',
          style: TextStyle(
            fontSize: 40,
            height: 1.05,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.8,
            color: webGreenDark,
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Homemade food from neighbours cooking nearby. Pickup from the cook.',
          style: TextStyle(
            fontSize: 15,
            height: 1.45,
            fontWeight: FontWeight.w500,
            color: Color(0xFF3E514B),
          ),
        ),
      ],
    );
    final visual = _HeroVisual(foods: widget.heroFoods);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        desktop ? 36 : 22,
        desktop ? 32 : 22,
        desktop ? 28 : 22,
        desktop ? 28 : 22,
      ),
      decoration: BoxDecoration(
        color: webHeroWash,
        borderRadius: BorderRadius.circular(24),
      ),
      child: desktop
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 6, child: copy),
                const SizedBox(width: 24),
                Expanded(flex: 5, child: visual),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [copy, const SizedBox(height: 18), visual],
            ),
    );
  }

  Widget _readySection() {
    return Padding(
      key: _readyKey,
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const WebSectionHeader(
            eyebrow: 'Order now',
            title: 'Ready right now',
            subtitle: 'Listings you can add to the cart today.',
          ),
          const SizedBox(height: 14),
          WebReadyNowStrip(
            items: widget.readyNow,
            cartQtyFor: widget.cartQtyFor,
            onAdd: widget.onAdd,
            onRemove: widget.onRemove,
            onOpen: widget.onOpenFood,
          ),
        ],
      ),
    );
  }

  Widget _foodSection({
    Key? key,
    required String eyebrow,
    required String title,
    required List<FoodItem> items,
    HomeListingReach? reach,
  }) {
    final expanded = reach != null && widget.expandedReach == reach;
    final preview = webIsDesktopWidth(MediaQuery.sizeOf(context).width) ? 8 : 6;
    final visible = expanded || items.length <= preview
        ? items
        : items.take(preview).toList();
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WebSectionHeader(
            eyebrow: eyebrow,
            title: title,
            trailing: reach == null || items.length <= preview
                ? null
                : _SeeAll(
                    expanded: expanded,
                    onTap: () => expanded
                        ? widget.onCollapseReach(reach)
                        : widget.onExpandReach(reach),
                  ),
          ),
          const SizedBox(height: 14),
          WebFoodGrid(
            items: visible,
            cartQtyFor: widget.cartQtyFor,
            onAdd: widget.onAdd,
            onRemove: widget.onRemove,
            onOpen: widget.onOpenFood,
            onSeller: (food) => widget.onOpenSeller(sellerFromListing(food)),
          ),
        ],
      ),
    );
  }

  Widget _sellerSection({
    required String eyebrow,
    required String title,
    required List<Seller> sellers,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WebSectionHeader(eyebrow: eyebrow, title: title),
          const SizedBox(height: 14),
          WebSellerGrid(
            sellers: sellers,
            detailFor: (seller) =>
                webSellerDetail(seller, widget.sellerListings),
            onTap: widget.onOpenSeller,
          ),
        ],
      ),
    );
  }

  Widget _reachBlock({
    Key? key,
    required String eyebrow,
    required String title,
    required String? subtitle,
    required List<Seller> sellers,
    required List<FoodItem> items,
    required HomeListingReach reach,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sellers.isNotEmpty)
            _sellerSection(eyebrow: eyebrow, title: title, sellers: sellers),
          if (items.isNotEmpty)
            _foodSection(
              eyebrow: sellers.isEmpty ? eyebrow : '',
              title: sellers.isEmpty ? title : 'Listings',
              items: items,
              reach: reach,
            ),
          if (subtitle != null && subtitle.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: webMuted,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _preorderSection({
    Key? key,
    required String title,
    required List<PreOrderCampaign> campaigns,
  }) {
    return Padding(
      key: key,
      padding: const EdgeInsets.only(top: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WebSectionHeader(
            eyebrow: 'Pre-order',
            title: title,
            trailing: campaigns.isEmpty
                ? null
                : TextButton(
                    onPressed: widget.onSeePreorders,
                    child: const Text(
                      'See all',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: webGreen,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 14),
          if (widget.preordersLoading && campaigns.isEmpty)
            const SizedBox(height: 120, child: _BlockLine())
          else
            SizedBox(
              height: 168,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: campaigns.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final campaign = campaigns[index];
                  return _WebPreorderCard(
                    campaign: campaign,
                    isOwn: campaign.sellerId == widget.viewerUserId,
                    onTap: () => widget.onOpenCampaign(campaign),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _emptySociety() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: webLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'No sellers available in your society yet',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: webInk,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Be the first one to share homemade food in your community. Discover home food from nearby societies.',
            style: TextStyle(
              fontSize: 14,
              height: 1.4,
              color: webMuted,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: widget.onStartSelling,
                style: FilledButton.styleFrom(backgroundColor: webGreen),
                child: const Text('Start Selling'),
              ),
              OutlinedButton(
                onPressed: widget.onExploreNearby,
                style: OutlinedButton.styleFrom(foregroundColor: webGreen),
                child: const Text('Explore Nearby'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _emptyCopy(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: webLine),
      ),
      child: Text(
        message,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: webMuted,
        ),
      ),
    );
  }

  String _searchTitle() {
    final count = widget.allFiltered.length;
    if (count == 0) return 'No matches';
    if (count == 1) return '1 match';
    return '$count matches';
  }

  String _emptyMessage() {
    if (widget.searchQuery.isNotEmpty) {
      return 'No listings match "${widget.searchQuery}".';
    }
    if (widget.selectedCategory != null) {
      return 'No listings in ${widget.selectedCategory} yet.';
    }
    return 'No listings yet. Be the first to add food from the seller dashboard.';
  }

  Widget _footer() {
    return WebFooter(
      onExplore: () => widget.onSelectTab(0),
      onOrders: () => widget.onSelectTab(1),
      onKitchen: () => widget.onSelectTab(2),
      onProfile: () => widget.onSelectTab(3),
      onHelp: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const HelpCenterScreen()),
        );
      },
      onPrivacy: () => _openLegal('Privacy Policy', kPrivacyPolicyBody),
      onTerms: () => _openLegal('Terms of Service', kTermsOfServiceBody),
    );
  }

  void _openLegal(String title, String content) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => LegalScreen(title: title, content: content),
      ),
    );
  }

  void _reveal(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
      alignment: 0.05,
    );
  }
}

class WebSectionHeader extends StatelessWidget {
  const WebSectionHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (eyebrow.isNotEmpty)
                Text(
                  eyebrow.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w800,
                    color: webGreen,
                  ),
                ),
              if (title.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 26,
                    height: 1.15,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                    color: webInk,
                  ),
                ),
              ],
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: webMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class _SeeAll extends StatelessWidget {
  const _SeeAll({required this.expanded, required this.onTap});

  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      child: Text(
        expanded ? 'Show less' : 'See all',
        style: const TextStyle(fontWeight: FontWeight.w800, color: webGreen),
      ),
    );
  }
}

class _HeroVisual extends StatelessWidget {
  const _HeroVisual({required this.foods});

  final List<FoodItem> foods;

  @override
  Widget build(BuildContext context) {
    if (foods.isEmpty) {
      return Container(
        height: 180,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFD7EBDF),
          borderRadius: BorderRadius.circular(18),
        ),
        child: const Icon(Icons.restaurant_rounded, color: webGreen, size: 42),
      );
    }
    final primary = foods.first;
    return SizedBox(
      height: 230,
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return ListingImage(
                    food: primary,
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                    borderRadius: 0,
                    iconSize: 48,
                  );
                },
              ),
            ),
          ),
          if (foods.length > 1) ...[
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return ListingImage(
                      food: foods[1],
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      borderRadius: 0,
                      iconSize: 36,
                    );
                  },
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WebPreorderCard extends StatelessWidget {
  const _WebPreorderCard({
    required this.campaign,
    required this.isOwn,
    required this.onTap,
  });

  final PreOrderCampaign campaign;
  final bool isOwn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final phase = campaign.homePhase();
    final when = switch (phase) {
      BuyerCampaignHomePhase.upcoming =>
        'Opens ${formatTime(campaign.orderOpenAt)}',
      _ => formatReadyAt(campaign.fulfilmentAt),
    };
    return SizedBox(
      width: 300,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: webLine),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 78,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: PreOrderCoverImage(
                          imageUrl: campaign.coverImageUrl,
                          height: 78,
                          borderRadius: 0,
                        ),
                      ),
                      Positioned(
                        left: 8,
                        top: 8,
                        child: PreOrderBadge(
                          compact: true,
                          label: buyerHomeBadgeLabel(campaign),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Text(
                    campaign.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: webInk,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                  child: Text(
                    isOwn ? 'Your campaign' : campaign.sellerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: webMuted,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                  child: Text(
                    '${formatMoney(campaign.startingPrice)} · $when',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: webGreen,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BlockLine extends StatelessWidget {
  const _BlockLine();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFE4EBE6),
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}
