import 'package:flutter/material.dart';

import '../models/data.dart';
import '../models/food_type.dart';
import '../widgets/listing_image.dart';
import '../widgets/listing_purchase_slot.dart';
import '../widgets/listing_rating_mark.dart';
import '../widgets/listing_type_badge.dart';
import '../widgets/listing_portion_caption.dart';
import '../widgets/made_to_order_hint.dart';
import '../widgets/recurring_availability_hint.dart';
import 'web_breakpoints.dart';

class WebFoodCard extends StatelessWidget {
  const WebFoodCard({
    super.key,
    required this.food,
    required this.cartQty,
    required this.onAdd,
    required this.onRemove,
    required this.onOpen,
    required this.onSeller,
  });

  final FoodItem food;
  final int cartQty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onOpen;
  final VoidCallback onSeller;

  @override
  Widget build(BuildContext context) {
    final ratingLabel = food.reviewCount > 0
        ? food.rating.toStringAsFixed(1)
        : '0 review';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: webLine),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 148,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return ListingImage(
                            food: food,
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                            borderRadius: 0,
                            iconSize: 40,
                          );
                        },
                      ),
                    ),
                    Positioned(
                      left: 10,
                      top: 10,
                      child: ListingTypeBadge(food: food, compact: true),
                    ),
                    Positioned(
                      right: 10,
                      top: 10,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (food.isNewListing()) ...[
                            const ListingNewChip(dense: true),
                            const SizedBox(width: 6),
                          ],
                          _RatingPill(
                            label: ratingLabel,
                            showStar: food.reviewCount > 0,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (food.foodType != null) ...[
                      _DietMark(foodType: food.foodType!),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        food.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: webInk,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
                child: GestureDetector(
                  onTap: onSeller,
                  child: Text(
                    food.sellerName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: webGreen,
                    ),
                  ),
                ),
              ),
              if (food.homePlaceLabel.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
                  child: Text(
                    food.homePlaceLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: webMuted,
                    ),
                  ),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 2, 12, 0),
                child: SizedBox.shrink(),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: MadeToOrderHint(food: food, compact: true),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: RecurringAvailabilityHint(food: food, compact: true),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '₹${food.price.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: webInk,
                            ),
                          ),
                          ListingPortionCaption(
                            food: food,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: webMuted,
                            ),
                          ),
                          if (listingSoldCaption(food.quantitySold)
                              .isNotEmpty)
                            Text(
                              listingSoldCaption(food.quantitySold),
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: webMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                    MarketplacePurchaseSlot(
                      food: food,
                      cartQty: cartQty,
                      addButton: _AddButton(label: 'Add', onTap: onAdd),
                      qtyStepper: _QtyStepper(
                        qty: cartQty,
                        onAdd: onAdd,
                        onRemove: onRemove,
                      ),
                      soldOut: const _SoldOutMark(),
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

class WebFoodGrid extends StatelessWidget {
  const WebFoodGrid({
    super.key,
    required this.items,
    required this.cartQtyFor,
    required this.onAdd,
    required this.onRemove,
    required this.onOpen,
    required this.onSeller,
  });

  final List<FoodItem> items;
  final int Function(FoodItem food) cartQtyFor;
  final void Function(FoodItem food) onAdd;
  final void Function(FoodItem food) onRemove;
  final void Function(FoodItem food) onOpen;
  final void Function(FoodItem food) onSeller;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = webFoodColumnCount(constraints.maxWidth);
        const gap = 16.0;
        final rows = <Widget>[];
        for (var i = 0; i < items.length; i += columns) {
          final slice = items.skip(i).take(columns).toList();
          final cells = <Widget>[];
          for (var col = 0; col < columns; col++) {
            if (col > 0) cells.add(const SizedBox(width: gap));
            cells.add(
              Expanded(
                child: col < slice.length
                    ? WebFoodCard(
                        food: slice[col],
                        cartQty: cartQtyFor(slice[col]),
                        onAdd: () => onAdd(slice[col]),
                        onRemove: () => onRemove(slice[col]),
                        onOpen: () => onOpen(slice[col]),
                        onSeller: () => onSeller(slice[col]),
                      )
                    : const SizedBox.shrink(),
              ),
            );
          }
          rows.add(
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: cells,
            ),
          );
          if (i + columns < items.length) rows.add(const SizedBox(height: gap));
        }
        return Column(children: rows);
      },
    );
  }
}

class WebReadyNowStrip extends StatelessWidget {
  const WebReadyNowStrip({
    super.key,
    required this.items,
    required this.cartQtyFor,
    required this.onAdd,
    required this.onRemove,
    required this.onOpen,
  });

  final List<FoodItem> items;
  final int Function(FoodItem food) cartQtyFor;
  final void Function(FoodItem food) onAdd;
  final void Function(FoodItem food) onRemove;
  final void Function(FoodItem food) onOpen;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final food = items[index];
          return _ReadyCard(
            food: food,
            cartQty: cartQtyFor(food),
            onAdd: () => onAdd(food),
            onRemove: () => onRemove(food),
            onOpen: () => onOpen(food),
          );
        },
      ),
    );
  }
}

class _ReadyCard extends StatelessWidget {
  const _ReadyCard({
    required this.food,
    required this.cartQty,
    required this.onAdd,
    required this.onRemove,
    required this.onOpen,
  });

  final FoodItem food;
  final int cartQty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Ink(
          width: 320,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: webLine),
          ),
          child: Row(
            children: [
              ListingImage(
                food: food,
                width: 96,
                height: 112,
                borderRadius: 0,
                iconSize: 28,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        food.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: webInk,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        food.sellerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: webMuted,
                        ),
                      ),
                      const Spacer(),
                      Row(
                        children: [
                          Text(
                            '₹${food.price.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: webInk,
                            ),
                          ),
                          const Spacer(),
                          MarketplacePurchaseSlot(
                            food: food,
                            cartQty: cartQty,
                            addButton: _AddButton(label: 'Add', onTap: onAdd),
                            qtyStepper: _QtyStepper(
                              qty: cartQty,
                              onAdd: onAdd,
                              onRemove: onRemove,
                            ),
                            soldOut: const _SoldOutMark(),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DietMark extends StatelessWidget {
  const _DietMark({required this.foodType});

  final String foodType;

  @override
  Widget build(BuildContext context) {
    final veg = foodType == foodTypeVeg;
    final color = veg ? const Color(0xFF14804A) : const Color(0xFFC0392B);
    return Container(
      width: 14,
      height: 14,
      margin: const EdgeInsets.only(top: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 1.4),
        borderRadius: BorderRadius.circular(3),
      ),
      alignment: Alignment.center,
      child: Container(
        width: 6,
        height: 6,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _RatingPill extends StatelessWidget {
  const _RatingPill({required this.label, this.showStar = true});

  final String label;
  final bool showStar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showStar) ...[
            const Icon(Icons.star_rounded, size: 13, color: Color(0xFFC48A12)),
            const SizedBox(width: 2),
          ],
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: webInk,
            ),
          ),
        ],
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: webGreen,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.qty,
    required this.onAdd,
    required this.onRemove,
  });

  final int qty;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: webGreen,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: onRemove,
            child: const Icon(Icons.remove, size: 16, color: Colors.white),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '$qty',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
          GestureDetector(
            onTap: onAdd,
            child: const Icon(Icons.add, size: 16, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _SoldOutMark extends StatelessWidget {
  const _SoldOutMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF3E4E2),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Sold out',
        style: TextStyle(
          color: Color(0xFF9A4444),
          fontSize: 11,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
