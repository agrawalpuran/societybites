import 'package:flutter/material.dart';

import '../models/data.dart';
import 'preorder_widgets.dart';

class ListingTypeBadge extends StatelessWidget {
  const ListingTypeBadge({
    super.key,
    required this.food,
    this.compact = true,
    this.dense = false,
  });

  final FoodItem food;
  final bool compact;
  final bool dense;

  static String labelFor(FoodItem food) {
    if (food.isPreOrder || food.isPreOrderCatalog) return 'PRE-ORDER';
    if (food.isMadeToOrder) return 'MADE TO ORDER';
    return 'REGULAR';
  }

  @override
  Widget build(BuildContext context) {
    if (food.isPreOrder || food.isPreOrderCatalog) {
      return PreOrderBadge(compact: true, dense: dense);
    }

    final madeToOrder = food.isMadeToOrder;
    final background = madeToOrder
        ? const Color(0xFFF3EEF8)
        : const Color(0xFFE8F5EE);
    final foreground = madeToOrder
        ? const Color(0xFF5A3E8A)
        : const Color(0xFF0E5A47);
    final fontSize = dense ? 8.0 : (compact ? 9.0 : 10.0);

    return Container(
      key: const Key('listing-type-badge'),
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 5 : (compact ? 7 : 9),
        vertical: dense ? 1 : (compact ? 3 : 4),
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
          fontSize: fontSize,
          letterSpacing: dense ? .2 : (compact ? .4 : .6),
          fontWeight: FontWeight.w700,
          height: 1.15,
        ),
      ),
    );
  }
}
