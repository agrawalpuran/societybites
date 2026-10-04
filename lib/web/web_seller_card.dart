import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/data.dart';
import '../widgets/seller_avatar.dart';
import 'web_breakpoints.dart';

class WebSellerCard extends StatelessWidget {
  const WebSellerCard({
    super.key,
    required this.seller,
    required this.detail,
    required this.onTap,
  });

  final Seller seller;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final rating = seller.reviewCount > 0
        ? seller.rating.toStringAsFixed(1)
        : 'New';
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: webLine),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _avatar(),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          seller.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: webInk,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            const Icon(
                              Icons.star_rounded,
                              size: 14,
                              color: Color(0xFFC48A12),
                            ),
                            const SizedBox(width: 2),
                            Text(
                              rating,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: webInk,
                              ),
                            ),
                            if (seller.reviewCount > 0) ...[
                              const SizedBox(width: 4),
                              Text(
                                '(${seller.reviewCount})',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: webMuted,
                                  fontWeight: FontWeight.w600,
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
              if (seller.hasOrderableItems && detail.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: FontWeight.w500,
                    color: webMuted,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Text(
                seller.hasOrderableItems
                    ? 'View menu'
                    : sellerNotAvailableLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: seller.hasOrderableItems ? webGreen : webMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _avatar() {
    final avatar = SellerAvatar(
      radius: 22,
      backgroundColor: seller.avatarColor,
      photoUrl: seller.profilePhotoUrl,
      fallback: Icon(seller.avatarIcon, color: webGreen, size: 20),
    );
    if (seller.hasOrderableItems) return avatar;
    return ClipOval(
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 2.4, sigmaY: 2.4),
        child: avatar,
      ),
    );
  }
}

class WebSellerGrid extends StatelessWidget {
  const WebSellerGrid({
    super.key,
    required this.sellers,
    required this.detailFor,
    required this.onTap,
  });

  final List<Seller> sellers;
  final String Function(Seller seller) detailFor;
  final void Function(Seller seller) onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = webSellerColumnCount(constraints.maxWidth);
        const gap = 16.0;
        final rows = <Widget>[];
        for (var i = 0; i < sellers.length; i += columns) {
          final slice = sellers.skip(i).take(columns).toList();
          final cells = <Widget>[];
          for (var col = 0; col < columns; col++) {
            if (col > 0) cells.add(const SizedBox(width: gap));
            cells.add(
              Expanded(
                child: col < slice.length
                    ? WebSellerCard(
                        seller: slice[col],
                        detail: detailFor(slice[col]),
                        onTap: () => onTap(slice[col]),
                      )
                    : const SizedBox.shrink(),
              ),
            );
          }
          rows.add(
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: cells),
          );
          if (i + columns < sellers.length) {
            rows.add(const SizedBox(height: gap));
          }
        }
        return Column(children: rows);
      },
    );
  }
}

String webSellerDetail(Seller seller, List<FoodItem> listings) {
  final items = listings.where((food) => food.sellerId == seller.id).toList();
  String? category;
  for (final food in items) {
    if (food.listingCategories.isNotEmpty) {
      category = food.listingCategories.first;
      break;
    }
  }
  final place = seller.block.trim();
  final bits = <String>[
    if (category != null && category.isNotEmpty) category,
    if (place.isNotEmpty) place,
    if (items.isNotEmpty)
      items.length == 1 ? '1 listing' : '${items.length} listings',
  ];
  return bits.join(' · ');
}
