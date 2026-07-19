import 'package:flutter/material.dart';
import '../widgets/listing_image.dart';
import '../widgets/app_header.dart';
import '../models/data.dart';
import '../services/api_service.dart';
import 'checkout_screen.dart';

class FoodDetailScreen extends StatelessWidget {
  const FoodDetailScreen({super.key, required this.food});

  final FoodItem food;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAF9),
      body: Column(
        children: [
          Expanded(
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: _HeroSection(food: food, size: size)),
                SliverToBoxAdapter(child: _QuickInfoRow(food: food)),
                SliverToBoxAdapter(child: _SellerCard(food: food)),
                SliverToBoxAdapter(child: _StorySection(food: food)),
                SliverToBoxAdapter(child: _ReviewsSection(food: food)),
                const SliverToBoxAdapter(child: SizedBox(height: 20)),
              ],
            ),
          ),
          _BottomCta(food: food),
        ],
      ),
    );
  }
}

class _HeroSection extends StatelessWidget {
  const _HeroSection({required this.food, required this.size});
  final FoodItem food;
  final Size size;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        SizedBox(
          width: double.infinity,
          height: size.height * 0.38,
          child: ListingImage(
            food: food,
            width: double.infinity,
            height: size.height * 0.38,
            borderRadius: 32,
            iconSize: 120,
          ),
        ),
        SafeArea(
          child: AppHeader(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            leading: _CircleButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: () => Navigator.pop(context),
            ),
          ),
        ),
        Positioned(
          left: 20,
          bottom: 20,
          right: 20,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (food.reviewCount >= 5 && food.rating >= 4.5)
                    Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0E5A47),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'BESTSELLER',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ),
                    ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withAlpha(220),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 15, color: Colors.amber),
                        const SizedBox(width: 3),
                        Text(
                          food.rating > 0
                              ? '${food.rating}'
                              : 'New',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF3A4644),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                food.name,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: food.bgColor.computeLuminance() < 0.4
                      ? Colors.white
                      : const Color(0xFF101617),
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '₹${food.price.toStringAsFixed(0)} / portion',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: food.bgColor.computeLuminance() < 0.4
                      ? Colors.white70
                      : const Color(0xFF6A7774),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(220),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: const Color(0xFF3A4644)),
      ),
    );
  }
}

class _QuickInfoRow extends StatelessWidget {
  const _QuickInfoRow({required this.food});
  final FoodItem food;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
      child: Row(
        children: [
          Expanded(
            child: _InfoChip(
              label: 'AVAILABILITY',
              value: '5',
              sub: 'portions left',
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _InfoChip(
              label: 'PICKUP',
              value: '1:00 PM',
              sub: 'Lobby Area',
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.value,
    required this.sub,
  });
  final String label;
  final String value;
  final String sub;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8A9491),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
          Text(
            sub,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF8A9491),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerCard extends StatelessWidget {
  const _SellerCard({required this.food});
  final FoodItem food;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: const Color(0xFFE8F5EE),
            child: Icon(Icons.person_rounded,
                color: const Color(0xFF0E5A47), size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      food.sellerName,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF101617),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(Icons.verified_rounded,
                        size: 18, color: Color(0xFF0E5A47)),
                  ],
                ),
                Text(
                  'Unit 402, ${food.block}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6A7774),
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F5EE),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'VERIFIED RESIDENT',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0E5A47),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StorySection extends StatelessWidget {
  const _StorySection({required this.food});
  final FoodItem food;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFEAEFED)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The Story',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFFB85C3A),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Cooked for over 12 hours on a low flame, this ${food.name} is a signature recipe. '
              'We use whole black lentils and kidney beans, enriched with white butter '
              'and a touch of smoky charcoal flavor (dhungar). No artificial cream—just slow-cooked perfection.',
              style: const TextStyle(
                fontSize: 15,
                color: Color(0xFF3A4644),
                height: 1.55,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),
            if (food.tags.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: food.tags.map((t) => _Tag(t)).toList(),
              ),
          ],
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F7F6),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE0E5E3)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF3A4644),
        ),
      ),
    );
  }
}

class _ReviewsSection extends StatefulWidget {
  const _ReviewsSection({required this.food});
  final FoodItem food;

  @override
  State<_ReviewsSection> createState() => _ReviewsSectionState();
}

class _ReviewsSectionState extends State<_ReviewsSection> {
  List<Review> _reviews = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  Future<void> _loadReviews() async {
    try {
      final raw = await ApiService.getListingReviews(widget.food.id);
      if (!mounted) return;
      setState(() {
        _reviews = raw.map(Review.fromJson).toList();
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Text(
                'What neighbors say',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF101617),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_isLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(color: Color(0xFF0E5A47)),
              ),
            )
          else if (_reviews.isEmpty)
            const Text(
              'No reviews yet. Be the first to order and share feedback!',
              style: TextStyle(
                color: Color(0xFF6A7774),
                fontWeight: FontWeight.w500,
              ),
            )
          else ...[
            ..._reviews.map((r) => _ReviewCard(review: r)),
            if (_reviews.isNotEmpty) ...[
              const SizedBox(height: 16),
              _RatingSummary(reviews: _reviews),
            ],
          ],
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({required this.review});
  final Review review;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEAEFED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFF0F2F1),
                child: Text(
                  review.name[0],
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF3A4644),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                review.displayName,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF101617),
                ),
              ),
              const Spacer(),
              Row(
                children: List.generate(
                  5,
                  (i) => Icon(
                    Icons.star_rounded,
                    size: 16,
                    color: i < review.rating
                        ? Colors.amber
                        : const Color(0xFFD4DBD8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '"${review.comment}"',
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF4A5A57),
              fontStyle: FontStyle.italic,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            children: review.tags
                .map((t) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5EE),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        t,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0E5A47),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _RatingSummary extends StatelessWidget {
  const _RatingSummary({required this.reviews});

  final List<Review> reviews;

  double get _avg =>
      reviews.fold<double>(0, (sum, r) => sum + r.rating) / reviews.length;

  @override
  Widget build(BuildContext context) {
    final avg = _avg;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RatingBubble(label: 'OVERALL', value: avg, color: const Color(0xFFE8F5EE)),
        _RatingBubble(label: 'REVIEWS', value: reviews.length.toDouble(), color: const Color(0xFFFFE5D6)),
        _RatingBubble(label: 'RATING', value: avg, color: const Color(0xFFE8F0F5)),
      ],
    );
  }
}

class _RatingBubble extends StatelessWidget {
  const _RatingBubble({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 90,
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              letterSpacing: 1,
              fontWeight: FontWeight.w700,
              color: Color(0xFF6A7774),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.toString(),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF101617),
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomCta extends StatelessWidget {
  const _BottomCta({required this.food});
  final FoodItem food;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(12),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Total Price',
                  style: TextStyle(
                    fontSize: 13,
                    color: Color(0xFF8A9491),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  '₹${food.price.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF101617),
                  ),
                ),
              ],
            ),
            const Spacer(),
            SizedBox(
              height: 54,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CheckoutScreen(
                        cartItems: [CartItem(food: food)],
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0E5A47),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                ),
                icon: const Icon(Icons.shopping_cart_rounded, size: 20),
                label: const Text(
                  'Order Now',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
