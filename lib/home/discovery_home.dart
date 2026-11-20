import 'package:flutter/material.dart';

import '../models/data.dart';
import '../models/selling_reach.dart';
import 'chef_hunt_card.dart';
import '../screens/explore_nearby_screen.dart';
import '../screens/food_detail_screen.dart';
import '../web/web_breakpoints.dart';
import '../widgets/app_header.dart';
import '../widgets/listing_buyer_price.dart';
import '../widgets/listing_image.dart';

/// Inspiration only. These are not live catalogue filters.
class DiscoveryFoodCategory {
  const DiscoveryFoodCategory({required this.title, required this.asset});

  final String title;
  final String asset;
}

const discoveryFoodCategories = <DiscoveryFoodCategory>[
  DiscoveryFoodCategory(
    title: 'Breakfast & Brunch',
    asset: 'assets/images/discovery/breakfast.jpg',
  ),
  DiscoveryFoodCategory(
    title: 'Evening Snacks',
    asset: 'assets/images/discovery/snacks.jpg',
  ),
  DiscoveryFoodCategory(
    title: 'Bakes & Desserts',
    asset: 'assets/images/guest/hero_food_3.jpg',
  ),
  DiscoveryFoodCategory(
    title: 'Everyday Meals',
    asset: 'assets/images/guest/hero_food_2.jpg',
  ),
  DiscoveryFoodCategory(
    title: 'Fresh & Dairy',
    asset: 'assets/images/discovery/dairy.jpg',
  ),
  DiscoveryFoodCategory(
    title: 'Pickles & Homemade',
    asset: 'assets/images/discovery/pickles.jpg',
  ),
];

const discoveryNearbyPreviewCount = 8;

/// Why this screen is empty. [radiusKm] is the city's configured reach.
String discoveryEmptyKitchenLine(double? radiusKm) {
  if (radiusKm == null || radiusKm <= 0) {
    return 'No home kitchens are selling in your society or neighbourhood yet.';
  }
  final km = formatReachRadiusKm(radiusKm);
  return 'No home kitchens are selling in your society or within ~$km km yet.';
}

/// State 1. Nearby dishes come from the feed Home already loaded.
class DiscoveryHome extends StatelessWidget {
  const DiscoveryHome({
    super.key,
    required this.nearbyListings,
    this.onStartSelling,
    this.onDiscoverNearby,
    this.onRefresh,
    this.neighbourhoodRadiusKm,
    this.showCookInvite = true,
    this.showChefHunt = false,
    this.chefWing = 'your wing',
    this.chefSocietyName,
    this.onChefHuntInvite,
  });

  final List<FoodItem> nearbyListings;
  final double? neighbourhoodRadiusKm;
  final VoidCallback? onStartSelling;
  final VoidCallback? onDiscoverNearby;
  final VoidCallback? onRefresh;

  /// Hidden once this account already sells.
  final bool showCookInvite;

  /// Logged-in nomination card at the bottom of Discovery.
  final bool showChefHunt;
  final String chefWing;
  final String? chefSocietyName;
  final Future<void> Function(String message)? onChefHuntInvite;

  @override
  Widget build(BuildContext context) {
    final nearby = nearbyListings.take(discoveryNearbyPreviewCount).toList();
    return ColoredBox(
      color: const Color(0xFFF8FAF9),
      child: RefreshIndicator(
        color: webGreen,
        onRefresh: () async {
          onRefresh?.call();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 28),
          children: [
            if (!useWebMarketplaceLayout(context)) const AppHeader(),
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _DiscoveryHero(),
                    if (nearby.isNotEmpty) _NearbyToday(listings: nearby),
                    const _DiscoveryCategories(),
                    if (showCookInvite) const _CommunityKitchen(),
                    if (showChefHunt)
                      ChefHuntCard(
                        wingLabel: chefWing,
                        societyName: chefSocietyName,
                        onInvite: onChefHuntInvite,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiscoveryHero extends StatelessWidget {
  const _DiscoveryHero();

  @override
  Widget build(BuildContext context) {
    final home = context.findAncestorWidgetOfExactType<DiscoveryHome>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: ColoredBox(
          color: webGreenDark,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Image(
                image: AssetImage('assets/images/guest/hero_food_1.jpg'),
                height: 150,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Homemade Food is Coming to Your Society',
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          height: 1.2,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        discoveryEmptyKitchenLine(home?.neighbourhoodRadiusKm),
                        maxLines: 1,
                        softWrap: false,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          height: 1.2,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Freshly cooked dishes made with passion and shared with neighbours, delivered right to your door.',
                      style: TextStyle(
                        color: Color(0xFFE7F3EE),
                        fontSize: 13,
                        height: 1.35,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: FilledButton(
                            onPressed: () {
                              final action = home?.onDiscoverNearby;
                              if (action != null) {
                                action();
                                return;
                              }
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => ExploreNearbyScreen(
                                    onStartSelling: home?.onStartSelling,
                                  ),
                                ),
                              );
                            },
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.white,
                              foregroundColor: webGreen,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 12,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                              ),
                            ),
                            child: const Text(
                              'Discover What\'s Cooking',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                        if (home?.showCookInvite != false &&
                            home?.onStartSelling != null) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: home?.onStartSelling,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 12,
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  height: 1.2,
                                ),
                              ),
                              child: const Text(
                                'Become the First Chef',
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        ],
                      ],
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

class _DiscoveryCategories extends StatelessWidget {
  const _DiscoveryCategories();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 18, 20, 4),
          child: Text(
            'What neighbours love to cook',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: webInk,
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Text(
            'Ideas for home kitchens. Nothing here is for sale yet.',
            style: TextStyle(fontSize: 13, color: webMuted, height: 1.3),
          ),
        ),
        _DiscoveryRail(
          height: 132,
          itemCount: discoveryFoodCategories.length,
          separatorWidth: 10,
          itemBuilder: (context, index) {
              final category = discoveryFoodCategories[index];
              return SizedBox(
                width: 132,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.asset(
                        category.asset,
                        height: 88,
                        width: 132,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      category.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: webInk,
                      ),
                    ),
                  ],
                ),
              );
            },
        ),
      ],
    );
  }
}

/// Horizontal row that fades a clipped card and offers a chevron when more
/// items sit outside the viewport.
class _DiscoveryRail extends StatefulWidget {
  const _DiscoveryRail({
    required this.height,
    required this.itemCount,
    required this.separatorWidth,
    required this.itemBuilder,
  });

  final double height;
  final int itemCount;
  final double separatorWidth;
  final Widget Function(BuildContext context, int index) itemBuilder;

  @override
  State<_DiscoveryRail> createState() => _DiscoveryRailState();
}

class _DiscoveryRailState extends State<_DiscoveryRail> {
  final _controller = ScrollController();
  var _canBack = false;
  var _canForward = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncEnds);
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncEnds());
  }

  @override
  void didUpdateWidget(_DiscoveryRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.itemCount != widget.itemCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncEnds();
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_syncEnds);
    _controller.dispose();
    super.dispose();
  }

  void _syncEnds() {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final canBack = position.pixels > 1;
    final canForward = position.maxScrollExtent - position.pixels > 1;
    if (canBack == _canBack && canForward == _canForward) return;
    setState(() {
      _canBack = canBack;
      _canForward = canForward;
    });
  }

  void _step(int direction) {
    if (!_controller.hasClients) return;
    final position = _controller.position;
    final delta = position.viewportDimension * 0.72 * direction;
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: Stack(
        children: [
          ListView.separated(
            controller: _controller,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: widget.itemCount,
            separatorBuilder: (_, _) => SizedBox(width: widget.separatorWidth),
            itemBuilder: widget.itemBuilder,
          ),
          if (_canBack) _edgeFade(forward: false),
          if (_canForward) _edgeFade(forward: true),
          if (_canBack) _chevron(forward: false),
          if (_canForward) _chevron(forward: true),
        ],
      ),
    );
  }

  Widget _edgeFade({required bool forward}) {
    const page = Color(0xFFF8FAF9);
    return Positioned(
      left: forward ? null : 0,
      right: forward ? 0 : null,
      top: 0,
      bottom: 0,
      width: 64,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: forward ? Alignment.centerLeft : Alignment.centerRight,
              end: forward ? Alignment.centerRight : Alignment.centerLeft,
              colors: [page.withValues(alpha: 0), page],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chevron({required bool forward}) {
    return Positioned(
      left: forward ? null : 6,
      right: forward ? 6 : null,
      top: 0,
      bottom: 0,
      child: Center(
        child: Material(
          color: Colors.white,
          shape: const CircleBorder(),
          elevation: 2,
          child: IconButton(
            tooltip: forward ? 'Show more' : 'Show previous',
            visualDensity: VisualDensity.compact,
            onPressed: () => _step(forward ? 1 : -1),
            icon: Icon(
              forward ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
              color: webGreen,
            ),
          ),
        ),
      ),
    );
  }
}

class _CommunityKitchen extends StatelessWidget {
  const _CommunityKitchen();

  @override
  Widget build(BuildContext context) {
    final home = context.findAncestorWidgetOfExactType<DiscoveryHome>();
    final startSelling = home?.onStartSelling;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F1E8),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'Why Cook on SocietyEats?',
                    style: TextStyle(
                      fontSize: 20,
                      height: 1.2,
                      fontWeight: FontWeight.w800,
                      color: webInk,
                    ),
                  ),
                ),
                SizedBox(width: 8),
                _CookMark(),
              ],
            ),
            const SizedBox(height: 14),
            const _CookPoint(
              icon: Icons.schedule_rounded,
              title: 'Cook on your schedule',
              body:
                  'Sell 4 plates or 20. Open your kitchen only when you feel like preparing food.',
            ),
            const SizedBox(height: 12),
            const _CookPoint(
              icon: Icons.place_outlined,
              title: 'Zero delivery headaches',
              body:
                  'Neighbors collect from your door or drop orders straight at Block D reception.',
            ),
            const SizedBox(height: 12),
            const _CookPoint(
              icon: Icons.verified_user_outlined,
              title: 'Safe, verified society circle',
              body:
                  'Strictly gated access. All diners and chefs are verified apartment residents.',
            ),
            if (startSelling != null) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: startSelling,
                  style: FilledButton.styleFrom(
                    backgroundColor: webGreenDark,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    textStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                    shape: const StadiumBorder(),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('Start Your Home Kitchen Today'),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.home_outlined, size: 14, color: webMuted),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '100% Home Cooked  ·  Zero Commercial Cloud Kitchens',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, height: 1.3, color: webMuted),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CookMark extends StatelessWidget {
  const _CookMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Icon(Icons.soup_kitchen_rounded, size: 20, color: webGreen),
    );
  }
}

class _CookPoint extends StatelessWidget {
  const _CookPoint({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: const BoxDecoration(
            color: Color(0xFFE7F3EE),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: webGreen),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: webInk,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: const TextStyle(fontSize: 13, height: 1.35, color: webMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NearbyToday extends StatelessWidget {
  const _NearbyToday({required this.listings});

  final List<FoodItem> listings;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ordering today from nearby societies',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: webInk,
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Your society has no dishes yet. These are from nearby societies and can be ordered now.',
                style: TextStyle(fontSize: 13, height: 1.3, color: webMuted),
              ),
            ],
          ),
        ),
        _DiscoveryRail(
          height: 214,
          itemCount: listings.length,
          separatorWidth: 12,
          itemBuilder: (context, index) {
            return _NearbyDishCard(food: listings[index]);
          },
        ),
      ],
    );
  }
}

class _NearbyDishCard extends StatelessWidget {
  const _NearbyDishCard({required this.food});

  final FoodItem food;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 168,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => FoodDetailScreen(food: food)),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ListingImage(food: food, height: 96, width: 152, borderRadius: 12),
                const SizedBox(height: 8),
                Text(
                  food.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: webInk,
                  ),
                ),
                Text(
                  food.sellerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: webMuted),
                ),
                const Spacer(),
                ListingBuyerPriceText(
                  food: food,
                  showBadge: false,
                  chargedStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: webGreen,
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
