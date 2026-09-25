import 'package:flutter/material.dart';

import '../models/data.dart';
import 'preorder_widgets.dart';

class ListingTypeBadge extends StatelessWidget {
  const ListingTypeBadge({
    super.key,
    required this.food,
    this.compact = true,
  });

  final FoodItem food;
  final bool compact;

  static String labelFor(FoodItem food) {
    if (food.isPreOrder || food.isPreOrderCatalog) return 'PRE-ORDER';
    if (food.isMadeToOrder) return 'MADE TO ORDER';
    return 'REGULAR';
  }

  @override
  Widget build(BuildContext context) {
    if (food.isPreOrder || food.isPreOrderCatalog) {
      return PreOrderBadge(compact: compact);
    }

    final madeToOrder = food.isMadeToOrder;
    final background = madeToOrder
        ? const Color(0xFFF3EEF8)
        : const Color(0xFFE8F5EE);
    final foreground = madeToOrder
        ? const Color(0xFF5A3E8A)
        : const Color(0xFF0E5A47);

    return Container(
      key: const Key('listing-type-badge'),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 3 : 4,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        labelFor(food),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: foreground,
          fontSize: compact ? 9 : 10,
          letterSpacing: compact ? .4 : .6,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
