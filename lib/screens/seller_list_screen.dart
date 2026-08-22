import 'package:flutter/material.dart';

import '../models/data.dart';
import '../widgets/preorder_widgets.dart';

class SellerListScreen extends StatelessWidget {
  const SellerListScreen({
    super.key,
    required this.sellers,
    required this.onSellerTap,
  });

  final List<Seller> sellers;
  final ValueChanged<Seller> onSellerTap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: preorderBackground,
      appBar: AppBar(
        backgroundColor: preorderBackground,
        foregroundColor: preorderText,
        elevation: 0,
        title: const Text(
          'Sellers',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView.separated(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 30),
        itemCount: sellers.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final seller = sellers[index];
          return Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              onTap: () => onSellerTap(seller),
              borderRadius: BorderRadius.circular(18),
              child: Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: preorderBorder),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 27,
                      backgroundColor: seller.avatarColor,
                      child: Icon(
                        seller.avatarIcon,
                        color: preorderGreen,
                        size: 27,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            seller.name,
                            style: const TextStyle(
                              color: preorderText,
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (seller.block.isNotEmpty &&
                              seller.block != 'Block ?') ...[
                            const SizedBox(height: 3),
                            Text(
                              seller.block,
                              style: const TextStyle(
                                color: preorderMuted,
                                fontSize: 13,
                              ),
                            ),
                          ],
                          if (seller.rating > 0) ...[
                            const SizedBox(height: 3),
                            Text(
                              '⭐ ${seller.rating.toStringAsFixed(1)}'
                              '${seller.reviewCount > 0 ? ' · ${seller.reviewCount} reviews' : ''}',
                              style: const TextStyle(
                                color: preorderMuted,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: Color(0xFFADB5B2),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
