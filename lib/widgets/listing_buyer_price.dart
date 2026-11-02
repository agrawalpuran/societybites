import 'package:flutter/material.dart';

import '../models/data.dart';
import '../models/listing_discount.dart';
import '../utils/listing_portion_label.dart';

/// Buyer price with optional strike-through regular amount and % off.
class ListingBuyerPriceText extends StatelessWidget {
  const ListingBuyerPriceText({
    super.key,
    required this.food,
    this.variants = const [],
    this.useCardLabel = false,
    this.alignEnd = false,
    this.chargedStyle,
    this.regularStyle,
    this.showBadge = true,
    this.saleOnOneLine = false,
    this.quote,
  });

  final FoodItem food;
  final List<FoodItem> variants;
  final bool useCardLabel;
  final bool alignEnd;
  final TextStyle? chargedStyle;
  final TextStyle? regularStyle;
  final bool showBadge;

  /// Keep the struck price and percent on one line. Card slots have a fixed height.
  final bool saleOnOneLine;

  /// When set, skip [listingDisplayPrice] (e.g. historical order snapshots).
  final ListingDisplayPrice? quote;

  @override
  Widget build(BuildContext context) {
    final display = quote ??
        (variants.length > 1
            ? listingDisplayPrice(cheapestBuyerVariant(variants))
            : listingDisplayPrice(food));
    final chargedLabel = useCardLabel
        ? listingCardPriceLabel(food, variants: variants)
        : '₹${display.chargedPrice.toStringAsFixed(0)}';
    final percent = display.discountPercent;
    final showPercent = showBadge &&
        display.saleActive &&
        percent != null &&
        listingDiscountPercentIsAllowed(percent.round());

    final charged = Text(
      chargedLabel,
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: chargedStyle ??
          const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF101617),
            height: 1.05,
          ),
    );
    if (!display.saleActive) return charged;

    final regularStyleResolved = regularStyle ??
        const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF8A9491),
          decoration: TextDecoration.lineThrough,
        );
    final regular = Text(
      '₹${display.regularPrice.toStringAsFixed(0)}',
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      style: regularStyleResolved,
    );
    final percentLabel = Text(
      '${percent?.round() ?? 0}% off',
      maxLines: 1,
      softWrap: false,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: Color(0xFF0E5A47),
      ),
    );
    final Widget saleLine = saleOnOneLine
        ? Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '₹${display.regularPrice.toStringAsFixed(0)}',
                  style: regularStyleResolved,
                ),
                if (showPercent)
                  TextSpan(
                    text: '  ${percent!.round()}% off',
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0E5A47),
                      decoration: TextDecoration.none,
                    ),
                  ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        : Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            children: [
              regular,
              if (showPercent) percentLabel,
            ],
          );

    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        charged,
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: saleLine,
        ),
      ],
    );
  }
}
